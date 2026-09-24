# Plan: release context

Execution plan for the five issues on RTNL, locks and the close of a runtime: #1050, #1055, #1069,
#1075 and #1087. Everything here was traced by reading, at Lunatik master
[c616f820e](https://github.com/luainkernel/lunatik/tree/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed)
and at kernels v6.6, v6.8 and v7.2, the ends of the range CI builds, with the tags in between where
a path changed. Nothing was reproduced: every case is a hang or a sleep under a spinlock on the host
that runs it. The line references are collected in `kernel-notes.md`.

## Where we are today

Four changes merged since the issues were filed, and the plan starts from them:

* #1045 (`5997f5743`, `717392aaa`) set `lunatik_rtnl`, the task a netdevice callback runs on, and
  `lunatik_checkrtnl` refuses there: `notifier.netdevice`, a send, a receive and a `setsockopt` past
  `SOL_SOCKET` on a netlink socket, `runtime:stop()`, `percpu:stop()` and their `__close`. What it
  does not reach it says: a release cannot refuse.
* #1065 (`8c6afe454`) made a finalizer the collector's to call: a script's own `obj:__gc()` no longer
  runs a release where the script is. The collector's calls still run wherever the collector steps.
* #1105 (`dd1f31447`) restores the RTNL holder around a nested netdevice dispatch, closing #1070.
* #1079 (`b4eba8cd1`) gave the device a kref of its own: a file's last close puts the runtime, but a
  runtime stopped before that has no state left to close, so that put frees and never closes.
* `f3d33bd10` documented the contract on `lunatik.runtime()` and `lunatik.percpu()`: a hook holds its
  runtime, so dropping the handle does not close a runtime a hook still holds; `d02dbf61c` tests the
  other half, a runtime without a hook closes when its last handle is collected.

What none of them touches is where a close runs when nobody called `stop()`.

## The merit of each issue

Each verdict names the path as reachable or not, from the source, with what merged since it was
filed taken into account.

### #1050: a socket closed from a netdevice callback

**Partly right, with the wrong socket in the title.** The path the body inherited from #1045 is the
multicast membership, and that is an IPv4 or a packet socket, not a netlink one: `inet_release`
calls `ip_mc_drop_socket`, which takes `rtnl_lock()` when the socket has a membership;
`inet6_release` does the same through `ipv6_sock_mc_close` and `ipv6_sock_ac_close` on kernels up
to v6.16; `packet_release` does it through `packet_flush_mclist`. On the task that holds RTNL each
is a self-deadlock. A netlink socket's `netlink_release` runs the protocol's `unbind` and `release`
callbacks, and at v6.6 and v6.8 neither rtnetlink nor genetlink registers one, so that close takes
neither RTNL nor `cb_lock`: the path the title names is unreachable there. From v6.9 genetlink
registers `genl_release`, which takes `cb_lock` for reading on every generic netlink socket's close,
and that is the lock #1055 orders with RTNL: a reader that arrives while a writer waits queues behind
it, and the cycle needs a genetlink request holding the lock for reading while it waits on RTNL.
So on the top of the range the netlink half is reachable too, as a cycle through `cb_lock` and not
as a wait on RTNL.

Two routes reach the close: the script's own `sock:close()` or `__close`, which is
`lunatik_closeobject` and can refuse, and the collector's, when the handle was dropped before the
callback and a GC step inside it finalizes the object, which cannot. Neither is answered by #1045 or
#1065. What remains open besides is `sock:bind()` on a generic netlink socket with groups, which
runs `genl_bind` on the binding task, `down_read(&cb_lock)` on every kernel in the range: the same
call #1045 refused through `NETLINK_ADD_MEMBERSHIP`, reachable through `bind` with no check.

Answered by phase 3 (the explicit routes and `bind`) and phase 4 (the collector's route).

### #1055: a channel made or released from a netdevice callback

**Right on both halves; the release half is reachable only through #1069's path.** The creation:
`genl_register_family` takes `cb_lock` for writing through `genl_lock_all`, a generic netlink
request holds it for reading across its `doit`, and an ethtool `doit` takes RTNL inside; a request
in flight when the callback registers a family leaves the two tasks waiting on each other. Nothing
refuses `netlink.channel.new` under RTNL today. The release: `genl_unregister_family` takes the same
write lock, and it runs at `lua_close`, since the channel is pinned in its runtime's registry. That
close reaches the callback's task through `runtime:stop()`, refused by #1045, or through the
collection of a child that holds a channel and no hook, which is #1069. The issue's own Update says
so.

Answered by phase 1 (the constructor) and phase 4 (the release).

### #1069: a child collected under RTNL closes on the callback's task

**Right, and the root of #1050's collector route and #1055's release half.** `lunatik.runtime()`
hands back the one reference a child starts with; a script that drops it leaves the child to the
collector; a GC step in a netdevice callback runs `lunatik_deleteobject`, whose put is the last, and
`lunatik_releaseruntime` calls `lua_close` on the task that holds RTNL, running every release of the
child's state there: a socket with a membership waits on RTNL, a channel waits on `cb_lock`. A child
holding a netdevice block does not close this way, since the block holds its runtime. #1045 and
#1065 refuse calls a script makes; the collector's put refuses nothing.

The shapes the issue offers, pinning the child in the parent's registry or documenting that a child
is stopped rather than dropped, both change the contract `d02dbf61c` tests and `f3d33bd10`
documents, a runtime closing when its last handle is collected, and neither covers a socket
collected in the callback's own state. Answered by phase 4.

### #1075: a table entry's put closes a runtime under the table spinlock

**Right, and wider than a runtime.** Every `rcu.table` is a SOFTIRQ class object, so `luarcu_setvalue`
holds `spin_lock_bh` while `luarcu_free` puts the value of the entry it replaces or removes. A value
is any shareable Lunatik object, so a socket can be that entry as well as a runtime: a TCP socket's
release reaches `tcp_close` and `lock_sock`, whose `might_sleep()` fires under the spinlock; a
runtime's `lua_close` runs every release of its state there. The small shape the issue names,
putting the old entry after the unlock, removes the spinlock but leaves the context: a softirq
runtime can write a shared table from its hook, and the put then closes the state in softirq. The
CLI's own path is safe, since `runner.stop` stops before it clears the entry, and a percpu object
dropped without shared data closes its runtimes wherever its own last put runs, this entry among
them.

Answered by phase 4, which covers both the spinlock and the context; the put-after-unlock shape is
written up below as the first shape weighed and not taken.

### #1087: a thread's stop from a netdevice callback

**Right on the mechanism, wrong on the example, and reachable through a route the issue does not
name.** `thread:stop()` from a netdevice callback runs `kthread_stop` on the task that holds RTNL and
waits for the body. The example the issue gives, the kthread's put closing a state whose netdevice
block unregisters under RTNL, is unreachable on master by the cycle #1042 records: the block holds
its runtime, so the kthread's put is never the last. What is reachable on the kthread is a socket
with a membership or a channel, closed there when the thread's reference was the last, waiting on
RTNL or on `cb_lock` while the callback waits in `kthread_stop`. What is reachable without any
release is the body itself: a thread body that calls `notifier.netdevice`, sends a netlink request
or joins a multicast group waits on RTNL on its own task, which the refusal in #1045 cannot see,
since that task is not the holder; the callback's `kthread_stop` then waits for a body that waits
for the callback. The `-EINTR` arm puts on the caller's task and is #1069's class.

The body route decides the shape: no deferral of a release covers a body that waits on RTNL, so the
stop is refused under RTNL, as `runtime:stop()` is. Answered by phase 2; the release arms fall to
phase 4 for the case where the thread ends on its own.

## The deciding fact

A class release runs synchronously on the task that drops the object's last reference, in whatever
context that task is in. `lunatik_putobject` is `kref_put(&kref, lunatik_releaseobject)`, and
`lunatik_releaseobject` calls the class release in place. The puts that can be last, and where each
runs:

| Put | Runs on | Context it can be in | Can refuse |
|-----|---------|---------------------|------------|
| `runtime:stop()`, `percpu:stop()`, `__close`, `sock:close()` | the script's task | under RTNL in a netdevice callback | yes, and #1045 does for the first three |
| `lunatik_stop` from C | the module's task | process context, no lock | not needed |
| the collector's `__gc` (`lunatik_deleteobject`) | whatever task runs Lua, at any allocation's GC step | under RTNL, in a child resumed from the callback, in softirq for a softirq runtime | no |
| an `rcu.table` entry replaced or removed (`luarcu_free`) | the writer's task | under `spin_lock_bh`, and in softirq when the writer is a softirq runtime | no |
| a thread body's end (`luathread_func`) | the kthread | a task the RTNL holder may be waiting for in `kthread_stop` | no |
| a thread stopped before it ran (`-EINTR`) | the stopper's task | under RTNL | through the stop |
| a percpu object's release | wherever its last put runs | any of the above | no |
| a device file's last close (#1079) | the closing task | process context; the state is already closed, so the put frees | not needed |

And the releases that sleep or wait on a lock, with what pins them to `lua_close`:

| Class | What its release does | Pinned to `lua_close` by |
|-------|----------------------|--------------------------|
| runtime | `lua_close`: every release of the state | nothing: the handle, an entry or a thread can be the last reference |
| socket | `sock_release`: `rtnl_lock` for an IPv4 or packet membership, IPv6 through v6.16, `down_read(&cb_lock)` on a generic netlink socket from v6.9, `lock_sock` for TCP | nothing |
| notifier | `unregister_netdevice_notifier`: `pernet_ops_rwsem` and `rtnl_lock` | holds its runtime and its registry slot |
| netlink.channel | `genl_unregister_family`: `cb_lock` for writing and `genl_mutex` | its registry slot |
| netfilter | `nf_unregister_net_hook`: `nf_hook_mutex`, `synchronize_net` | holds its runtime and its registry slot |
| probe, fsnotify, hid, device | a mutex and a grace period each | hold their runtime and a registry slot |
| data, fifo, set, skb, task, thread, crypto, bpf map, the contexts | free, `kfree_skb`, `put_task_struct`, a put the kernel defers itself | not needed |

So the hazard is the product of two classes, runtime and socket, three puts that cannot refuse, and
three contexts: under RTNL, under a spinlock, and on a task the RTNL holder waits for. The premise
the tree was written on, "release always runs in process context (lua_close -> GC -> release)" in
`luanotifier_release`, holds when the last put is a `stop()` from process context off RTNL, and
nowhere else.

## The shapes, smallest first

1. **Document the limits.** On `lunatik.runtime()`, `socket.new` and `rcu.table`: a child is stopped,
   not dropped; a socket is not closed under RTNL; a runtime is not stored in a table. Costs nothing
   and makes nothing unreachable: every hang stays one dropped handle away, which is the conclusion
   #1042's Update already reached for the leak.
2. **Refuse the named calls.** `lunatik_checkrtnl` in `netlink.channel.new`, `thread:stop()`, and
   `sock:close()`, `__close` and `bind` where the kernel path waits on RTNL or `cb_lock`. One line
   and a test each, no contract beyond a refusal a script sees. Covers every route a script takes by
   name, and the whole of #1087, whose body route no other shape covers. Leaves the collector's put
   and the C puts: #1050's collector route, #1055's release half, #1069 and #1075.
3. **Stop the collector around the netdevice dispatch.** `lua_gc(L, LUA_GCSTOP)` before the
   callback and a restore after, in `luanotifier_netdevice_call`, as `lunatik_monitor` already does
   around a monitored method. Four lines. It covers the finalizers of the callback's own state and
   nothing else: a child resumed from the callback steps its own collector, the entry and thread
   puts are not the collector's, and `lunatik_monitor`'s `LUA_GCRESTART` re-enables the collector
   for the rest of the callback the first time it calls a monitored method, which every socket
   method is (filed as its own defect, since it also undoes a script's `collectgarbage("stop")`).
   Partial and holey.
4. **Put an `rcu.table`'s old entry after the unlock.** `luarcu_setvalue` unlinks under the lock and
   frees after it. Six lines, no contract change. Removes the spinlock from every release the table
   runs, for every class; leaves the softirq writer, whose put still closes a state in softirq, and
   nothing of the other four issues. Unnecessary once shape 6 is in: the put under the lock then
   only queues.
5. **Pin a child in its parent's registry** (#1069's shape). A runtime then closes only through
   `stop()`. Reverses the contract `f3d33bd10` documents and `d02dbf61c` tests, leaks every child a
   script drops, and covers no socket.
6. **Defer the release a class declares as sleeping, at a last put that is not a stop.** The runtime
   and the socket classes carry an option; `lunatik_releaseobject` on an object of such a class whose
   private is still set queues it on the core's own workqueue instead of releasing in place, and a
   worker runs the release in process context with no lock held. `stop()` and `close()` stay
   synchronous, since `lunatik_closeprivate` releases the private itself and the put that follows
   finds it NULL. Covers every unrefusable put, in every context, for every lock, and turns the
   premise in `luanotifier_release` into a fact by construction. Costs: a list node on every object,
   a workqueue in the core, a flush before the modules unload, and a contract change said on
   `lunatik.runtime()`: a collected runtime closes after the drop and off the dropping task, so a
   test that counts a module's use after `collectgarbage()` waits for it. Chosen, with shape 2 for
   the named calls; the two are complementary, not alternatives, since a synchronous `close()` under
   RTNL cannot be deferred without changing what `close()` means.
7. **Defer every release, of every class.** One rule, no option: simpler to state, and it puts a
   worker between a collected `data` buffer and its `kvfree`, a work item per collected object at
   every GC, for classes whose release is a free. Not taken; the option names the two classes that
   need it and a class added later declares it.
8. **Defer conditionally**, when `lunatik_isrtnl()` or `in_atomic()` holds. Both are proxies: the
   kernel's own comment on `in_atomic()` says it cannot see a spinlock held on a non-preemptible
   kernel, and neither predicate sees the kthread the RTNL holder waits for. Not taken.

## The impact on #1088

#1088 asks whether the core should carry one mechanism in which a binding declares the lock its
dispatch holds and an entry point declares the lock it takes, with RTNL as the first user. Read
against this plan:

* The five issues are not answered by it. A declared lock answers the puts a script makes by name,
  which shape 2 answers with three call sites of the check that exists; the puts that cannot refuse,
  which are the larger half here, need no knowledge of any lock once the release runs on a worker
  that holds none.
* It should not come first. Nothing in phases 1 to 4 would be written differently on top of it: a
  generic `lunatik_checkheld(L, LUNATIK_LOCK_RTNL)` replaces `lunatik_checkrtnl` name for name.
* Its shape, if it is taken later: one task pointer per lock in a small enum, `lunatik_sethold`,
  `lunatik_isholding` and `lunatik_checkhold`, each entry point naming the locks it must not run
  under. The pair matters, not the lock alone: taking RTNL under `cb_lock` is the kernel's own order
  (ethtool's `doit` does it), taking `cb_lock` under RTNL is the cycle, so an entry point declares
  what it must not run under, not what it takes, which is what #1045's one check already is.
* Its trigger stays what its body says: a second lock a dispatch holds. This plan adds none. #1089
  would, since a generic netlink `doit` runs under `cb_lock` and `genl_mutex`.

## The impact on #1089

A generic netlink control plane runs each request's `doit` on the requesting task with `cb_lock`
held for reading and, without `parallel_ops`, `genl_mutex`. Read against this plan:

* Who closes a runtime, and under what: a synchronous `stop` from a `doit` closes it on the
  requester's task under those locks. A channel's release then calls `genl_unregister_family`, whose
  `genl_lock_all` takes `cb_lock` for writing and `genl_mutex`, both held by the same task: a
  self-deadlock for every runtime that holds a channel, on every kernel in the range, with
  `parallel_ops` or without it. A release that takes RTNL under `cb_lock` follows the kernel's own
  order and does not deadlock by itself; it holds a genetlink reader across a wait on RTNL, and a
  netdevice callback on another task that closes a generic netlink socket on a kernel from v6.9 then
  queues on `cb_lock` behind any waiting writer, the three-task cycle #1050's netlink half is.
* So the control plane cannot close runtimes on the `doit` task, and cannot wait there for a worker
  that will need `cb_lock` for writing either. A `stop` request has to return before the close, with
  the close deferred, and its completion observed afterwards. Phase 4's worker is that mechanism;
  #1089 builds on it and does not need a second one.
* The character device keeps the one property the plan relies on today: the driver's task holds no
  kernel lock, so `runner.stop` there is the synchronous close every test and the CLI expect.
  Moving off it gives that up for every stop, not only the ones a script makes under RTNL.
* It adds hazards: the `doit`'s `cb_lock` is the second dispatch lock #1088 waits for, and #1070's
  nested dispatch becomes reachable if a request runs a script that sends generic netlink itself,
  since the recursive read on `cb_lock` queues behind a waiting writer like any other.
* The phases stay independent of #1089 and precede it. #1089's design note should record the four
  points above and take phase 4 as its base.

## Phases

Each phase is one pull request that reviews alone. The first three are independent of each other and
of the fourth; they are ordered by size. The fourth is the mechanism and the largest change.

### Phase 1: `netlink.channel.new` refuses under RTNL

`lunatik_checkrtnl` at the top of the constructor, the `@raise` naming it, and a test that creates a
channel from the replay a `notifier.netdevice` registration delivers and asserts the refusal, then
creates one after the registration returned. Files: `lib/luanetlink.c`, `tests/netlink/`,
`tests/README.md`. Answers #1055's creation half.

### Phase 2: `thread:stop()` refuses under RTNL

`lunatik_checkrtnl` in `luathread_stop` before anything else, the `@raise` saying why (the stop waits
for the body, and the body may wait on RTNL), a note on `thread.run` that a runtime a callback will
stop is stopped off RTNL, and a test that starts a thread whose body ends on its own, stops it from
the replay callback and gets the refusal, then stops it afterwards. Files: `lib/luathread.c`,
`tests/thread/`, `tests/README.md`. Answers #1087. A build without the refusal fails this test rather
than hanging, since the body ends and the runtime holds no release that takes RTNL.

### Phase 3: a socket refuses the close and the bind that wait on a lock its task holds

`luasocket_close` replaces `lunatik_closeobject` as `close` and `__close`: it refuses under RTNL when
the socket's release would take RTNL or `cb_lock`, read from what the release reads, and closes
otherwise. `luasocket_bind` refuses under RTNL on a netlink socket, as `send` and `receive` do. The
predicate, `luasocket_takesrtnl`: `AF_PACKET` always, since the membership list is private to
`af_packet.c`; `AF_INET` when `inet_sk(sk)->mc_list` is set; `AF_INET6` when `ipv6_mc_list` or
`ipv6_ac_list` is set, on kernels before v6.17, where the release no longer takes RTNL; `AF_NETLINK`
with `NETLINK_GENERIC` on kernels from v6.9, where `genl_release` takes `cb_lock`. The version guards
put the current kernel's shape in the `#if` arm. Files: `lib/luasocket.c`, `tests/socket/rtnl.{sh,lua}`,
`tests/README.md`. Answers #1050's explicit routes and the `bind` gap. A build without the refusal
wedges on the membership close, so the test skips unless the loaded `luasocket` is the installed one,
the way `rtnl.sh` already does for its inline refusals.

### Phase 4: a release nobody called runs on a worker

The core gains a class option, `LUNATIK_OPT_DEFERRED`, on the runtime and the socket classes; a list
node on `lunatik_object_t`; a workqueue of its own, unbound, created in `lunatik_init` and destroyed
in `lunatik_exit`; and `lunatik_flush`, which `lunatik_run_exit` calls after stopping the driver so
`lunatik unload` finds the bindings unpinned. `lunatik_releaseobject` on an object with the option
and a private still set adds it to the list and queues the work; the worker drains the list and
runs `lunatik_releaseprivate`, `lunatik_freelock` and `kfree` for each. Everything else is unchanged:
`lunatik_closeprivate` still releases in place, so `stop()`, `close()` and `lunatik_stop` are
synchronous and #1045's refusals stay where they are; an object whose private is NULL frees in place.

With it: `luanotifier_release`'s comment and `luanotifier_stop`'s doc block state the fact as
structural; `lunatik_releasepercpu`'s comment on the put in softirq says the put queues;
`lunatik.runtime()` and `lunatik.percpu()` say a collected runtime closes on a worker, after the drop;
`doc/capi.md` documents the option, `lunatik_flush` and the rule; `tests/runtime/collected.sh` waits
for the use count instead of reading it at once; and the new tests in `testing.md`. Files: `lunatik.h`,
`lunatik_obj.c`, `lunatik_core.c`, `lunatik_run.c`, `lunatik_percpu.c`, `lib/luasocket.c`,
`lib/luanotifier.c`, `doc/capi.md`, `tests/runtime/`, `tests/rcu/`, `tests/notifier/`,
`tests/README.md`, and the Object model section of `AGENTS.md`. Answers #1069, #1075, #1050's
collector route, #1055's release half and #1087's release arms.

The list node and one work item serialize the deferred closes in the order they were queued; a
`work_struct` per object would run them concurrently at four times the field. The serial shape is
proposed, and the phase measures nothing it does not need: a close waits on RTNL for as long as a
callback holds it, which the kernel keeps short.

## Non goals

* Changing whether a hook holds its runtime. #1077 keeps that question; phase 4 does not touch the
  reference a hook takes, and a child holding a hook still leaks when dropped, as documented.
* The generic lock mechanism of #1088, and the control plane of #1089. Both are read above for what
  this plan changes for them; neither is built here.
* Making `close()` or `stop()` asynchronous. A `close()` that returns before the port is free, or a
  `stop()` that returns before the hook is gone, changes what every test and the CLI rely on.
* A per-namespace RTNL. `rtnl_net_lock` arrives inside the range and the netdevice chain still
  asserts the global lock at v7.2; the refusal keys on the task that dispatches, not on the lock's
  scope.

## Risks

| Risk | Mitigation |
|------|-----------|
| A deferred close never runs, pinning a binding through `lunatik reload` | `lunatik_flush` in `lunatik_run_exit` and `destroy_workqueue` in `lunatik_exit`; the CLI's unload loop already repeats until nothing is removed, so a flush that runs in the first pass unpins what the second removes. |
| The worker blocks on a lock a script holds forever | The worker runs a `lua_close` with no lock of its own; what it waits on is RTNL or `cb_lock`, which the kernel holds briefly, or a runtime lock a thread body holds, which cannot be a last put since the thread holds a reference. |
| A script reads a name back too early: a family or a device registered by a collected child is still registered when the script registers it again | Documented on `lunatik.runtime()`: a script that needs the name back stops the runtime. |
| A test that counts a module's use after `collectgarbage()` reads it before the worker ran | `collected.sh` polls with a bound, as `orphan.sh` waits on the kernel's own timers. |
| The socket predicate reads a socket field the kernel changes | The three fields are on public structs and read where the release reads them; `kernel-notes.md` pins each at three tags, and the IPv6 arm carries the version its release changed at. |
| A refusal on `close` takes away closing a connection from a callback | The predicate keys on the membership, so a TCP or UDP socket without one still closes there. |

## Definition of done, per phase

1. builds clean on the target kernel, no new warnings, `make C=1` clean where a pointer annotation
   is touched;
2. the LDoc `@raise` on every entry point that gains a refusal, in the words of the message;
3. `doc/capi.md` updated for every C interface the phase adds;
4. the tests of `testing.md` for the phase, wired into the suite's `run.sh` and described in
   `tests/README.md`; every case that would wedge a host without the fix checks `/proc/kallsyms`
   or the loaded module's `srcversion` and skips;
5. `sudo lunatik test` passes whole;
6. the pull request that finishes the phase carries `Closes #<phase issue>` and closes the original
   issue the phase answers, named in the phase issue.

