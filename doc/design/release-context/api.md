# The interfaces: release context

What changes at the Lua and the C interfaces, phase by phase, and the reasons. The reference for each
method is the LDoc generated from the binding; what this document carries is the contract each phase
adds and what a script loses or gains. Where it and the code disagree, the code is right.

## Phase 1: `netlink.channel.new`

    @raise if called after module load, in a percpu runtime, or under RTNL: from a netdevice
      callback, and from any runtime or coroutine the callback runs; if the name is empty or too
      long, or if family registration fails

`genl_register_family` takes `cb_lock` for writing, and a generic netlink request holds it for
reading while it may wait on the RTNL this task holds. The refusal is `lunatik_checkrtnl` at the top
of the constructor, before the object is made. A script that needs a channel from a callback makes it
at load, which is where the doc block already says a channel is made.

## Phase 2: `thread:stop()`

    @raise "not allowed under RTNL" from a netdevice callback, in whatever runtime or coroutine its
      task runs: the stop waits for the thread's body, and a body that registers a netdevice notifier,
      sends a netlink request or joins a multicast group waits on the RTNL that task holds

The refusal covers both arms of the stop: the wait for a running body, and the `-EINTR` arm, which
puts the runtime on the calling task. `thread.run`'s doc block gains one sentence: a thread a callback
would stop is stopped off RTNL, from the script body, a later resume or another thread.

## Phase 3: `socket:close()`, `__close` and `socket:bind()`

    @function close
    @raise "not allowed under RTNL" from a netdevice callback, in whatever runtime or coroutine its
      task runs, on a socket whose release takes RTNL or waits on a lock ordered with it: an
      `AF_PACKET` socket; an `AF_INET` socket with a multicast membership; an `AF_INET6` socket with a
      multicast or an anycast membership, on a kernel before 6.17; a `NETLINK_GENERIC` socket, on a
      kernel from 6.9

    @function bind
    @raise ... or on a netlink socket under RTNL, as from a netdevice callback

`close` and `__close` become `luasocket_close`, which runs the check and then `lunatik_closeobject`.
The predicate, `luasocket_takesrtnl`, reads what the kernel's release reads: `inet_sk(sk)->mc_list`,
`inet6_sk(sk)->ipv6_mc_list` and `ipv6_ac_list`, `sk->sk_protocol`; `AF_PACKET` and `NETLINK_GENERIC`
are refused by family and protocol, since their membership lists are in structs no header exports.
Each version-dependent arm puts the current kernel's shape in the `#if` arm: from 6.17 the IPv6
release takes `lock_sock` and the arm reads no list; from 6.9 the generic netlink release takes
`cb_lock` and the arm refuses the protocol. What a script loses: closing such a socket from a
netdevice callback. What it keeps: closing a TCP or UDP socket with no membership there, which the
predicate lets through.

`bind` on a netlink socket takes `luasocket_checkrtnl`, the check `send` and `receive` already take:
`netlink_bind` runs the protocol's bind for each group in `nl_groups`, and genetlink's takes
`cb_lock` for reading, the same path `NETLINK_ADD_MEMBERSHIP` reaches through `setsockopt`, which
#1045 refuses.

## Phase 4: a release nobody called runs on a worker

### `lunatik.runtime()` and `lunatik.percpu()`

The paragraph on how a runtime closes gains its last clause:

> The runtime closes on `stop()`, when a to-be-closed variable holding it goes out of scope, or
> when its last reference is dropped, in which case it closes on a kernel worker after the drop,
> not on the task that dropped it: a hook or a name its script registered is released then, so a
> script that needs the name back stops the runtime instead of dropping it.

Nothing else on the page changes: a hook still holds its runtime, `stop()` is still synchronous and
still refused under RTNL.

### `socket.new`

One sentence on the object: a socket whose last reference is dropped is released on a kernel worker,
after the drop; `close()` releases it before returning.

### The C API (`doc/capi.md`)

```C
#define LUNATIK_OPT_DEFERRED	((__force lunatik_opt_t)(1U << 7))
void lunatik_flush(void);
```

`LUNATIK_OPT_DEFERRED` on a class says its release sleeps or waits on a lock: a put that drops the
last reference of an object of that class whose private is still set does not run the release on the
calling task but queues the object on the core's workqueue, where a worker runs the release, frees
the lock and the object, in process context with no lock held. `lunatik_closeprivate`, and so every
`stop()`, `close()` and `lunatik_stop`, still releases the private in place; the put that follows
finds it NULL and frees in place. The runtime and the socket classes carry the option; a class whose
release sleeps and whose object can be the value of an `rcu.table`, or is not pinned in a registry,
declares it too.

`lunatik_flush` waits for every queued release to finish. `lunatik_run_exit` calls it after stopping
the driver, so the modules a deferred close pins are free before the CLI removes them; `lunatik_exit`
destroys the workqueue, which flushes it. A C consumer that unloads while it may have dropped a
runtime calls it in its exit.

The `lunatik_isrtnl` paragraph loses its last sentence but one, since the entry points a release
reaches from a callback's task are now the ones that close in place, `stop()` and `close()`, and a
release nobody called never runs there.

`lunatik_object_t` gains one field, `struct llist_node deferred`, the link the core's list uses
between the last put and the worker.

### The Object model section of `AGENTS.md`

One paragraph, after "Cleanup belongs in an explicit `detach`/`stop`": a release runs on the task
that drops the last reference, and the collector, an `rcu.table` entry and a thread body drop
references on tasks a script does not choose; a class whose release sleeps declares
`LUNATIK_OPT_DEFERRED`, and its release then runs on the core's worker when nobody stopped the
object. A release that must run where the script is belongs to a `stop`, which can refuse.

### What a script observes

* A child dropped without a `stop()` closes a little later than today, off the task that dropped it.
  A script that reads back a name the child registered, a family or a device, immediately after
  the drop may find it still registered; it stops the child instead.
* `collectgarbage()` returns before the close ran. A test that counts a module's use after it waits.
* Nothing changes for `stop()`, `close()` or `runner.stop`.

