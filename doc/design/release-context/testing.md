# Testing: release context

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what it
prints to `dmesg`. Two existing tests are the models here, read them first: `tests/notifier/stop.sh`
probes from inside a netdevice callback, on the replay a registration delivers and on a live event,
and skips when the loaded core lacks the symbol that carries the refusal; `tests/socket/rtnl.sh`
does the same for refusals that are inline in a binding, skipping unless the loaded module's
`srcversion` is the installed one. `tests/runtime/collected.sh` counts a module's use to see a
runtime close.

## What every case here has in common

**A case that would wedge the host without its fix does not run without it.** A tree without a
refusal, or without the worker, does not fail these cases: the task waits on the lock it holds and
stays in D state, and only a reboot clears it. So a case whose stimulus reaches such a path checks
before it, in `/proc/kallsyms` or `/sys/module/<m>/srcversion`, that the loaded module carries the
fix, and skips when it does not. Which cases those are is said per phase below; the others
discriminate by the message they assert and fail, not hang, on a build without the fix.

**The stimulus is forced, not waited for.** Every "under RTNL" case runs its probe from the replay a
`notifier.netdevice` registration delivers inside the call, on the registering task, which holds
RTNL by construction; a live event on a dummy device brought up by the test covers the other task.

**Nothing an experiment does removes a guard.** Proving a refusal discriminates is done by the
message; a build with the guard removed reproduces the hang.

## Phase 1: `netlink.channel.new` under RTNL

| Case | Stimulus | Outcome asserted |
|------|----------|------------------|
| create from the replay | `netlink.channel.new` in the callback during registration | `"not allowed under RTNL"` |
| create from a live event | the same on the UP of a dummy device | the refusal |
| create after the registration returned | `netlink.channel.new` in the script body | a channel, and `genl` resolves the family by name |
| no Lua errors in the kernel log | `check_dmesg` | clean |

Without the refusal the create succeeds unless a genetlink request holding `cb_lock` is waiting on
RTNL at that instant; the case cannot rule that out on a host it does not own, so it skips unless the
loaded `luanetlink`'s `srcversion` is the installed one.

## Phase 2: `thread:stop()` under RTNL

| Case | Stimulus | Outcome asserted |
|------|----------|------------------|
| stop from the replay | `thread:stop()` on a thread whose body idles and ends on its own | the refusal |
| stop from a live event | the same on the UP of a dummy device | the refusal |
| stop after the callback returned | `thread:stop()` in the script body | accepted, and `thread:task()` reports the task ended |
| the thread's runtime is stopped off RTNL | `runner.stop` of the spawned script after the probe | the module's use count returns |
| no Lua errors in the kernel log | `check_dmesg` | clean |

The thread body ends on its own and its runtime holds no release that takes RTNL, so a build without
the refusal accepts the stop and fails the assertion; no skip is needed.

## Phase 3: a socket's `close`, `__close` and `bind` under RTNL

| Case | Socket | Stimulus in the replay | Outcome asserted |
|------|--------|------------------------|------------------|
| close with an IPv4 membership | UDP with `IP_ADD_MEMBERSHIP` joined before the registration | `sock:close()` | the refusal |
| close through a `<close>` local | the same socket, a local going out of scope | `__close` | the refusal |
| close without a membership | TCP or UDP with none | `sock:close()` | accepted |
| close an AF_PACKET socket | `AF_PACKET` raw | `sock:close()` | the refusal |
| close an IPv6 membership | UDP6 with `IPV6_ADD_MEMBERSHIP` | `sock:close()` | the refusal on a kernel before 6.17, accepted from 6.17 |
| close a generic netlink socket | `NETLINK_GENERIC` | `sock:close()` | the refusal on a kernel from 6.9, accepted before |
| close a route netlink socket | `NETLINK_ROUTE` | `sock:close()` | accepted |
| bind a generic netlink socket to a group | `NETLINK_GENERIC` | `sock:bind(0, group)` | the refusal |
| every refused close accepted afterwards | the same sockets, in the script body | `sock:close()` | accepted, and the module's use count returns |
| no Lua errors in the kernel log | `check_dmesg` | clean |

The kernel-dependent rows read `uname -r` and assert the arm the running kernel takes. Without the
refusal the first row wedges the host, so the test skips unless the loaded `luasocket`'s
`srcversion` is the installed one, and sends the wedging stimulus only once a row that cannot wedge
(the AF_PACKET close on a socket with no membership, which the refusal refuses by family) was
refused by the module that is loaded.

## Phase 4: a release nobody called runs on a worker

The matrix is the drop by the object by the outcome. The object is a child runtime whose script
holds what the row says and registers no hook, or a socket alone.

| Drop | Object | Where the drop runs | Outcome asserted |
|------|--------|---------------------|------------------|
| handle collected | runtime holding a UDP socket with an IPv4 membership | `collectgarbage()` in the replay callback | the callback returns; the module's use count returns within the bound; no hung task |
| handle collected | runtime holding a `netlink.channel` | the same | the same, and the family name resolves again afterwards |
| handle collected | a socket with an IPv4 membership, in the callback's own state | the same | the same |
| handle collected | runtime holding nothing | in the script body | the use count returns within the bound (`collected.sh`, with the wait) |
| handle collected | a percpu set | in the script body | the same (`collected.sh`) |
| entry replaced | runtime holding a TCP socket, stored in an `rcu.table` | a process runtime replaces the entry | the use count returns; `check_dmesg` finds no sleeping-in-atomic warning |
| entry removed | the same | `t.k = nil` from a softirq runtime's netfilter hook, fired by a ping to loopback | the same |
| entry replaced | a socket with a membership, as the value | a process runtime | the same |
| thread body ends | runtime holding a socket with a membership, run through `thread.run` with the handle dropped | the body returns | the use count returns; the kthread ended without waiting |
| percpu object dropped | a set without shared data, stored in an `rcu.table` and the entry removed | a process runtime | the use count returns |
| `stop()` | runtime holding a socket with a membership | the script body | synchronous: the use count returns before `stop()` returns |
| `stop()` under RTNL | the same | the replay callback | the refusal, unchanged |
| reload after a deferred close | a child collected at the end of a script | `lunatik reload` | every module replaced, none reported as loaded from another build |
| no Lua errors in the kernel log | `check_dmesg` | clean |

The first three rows and the two `rcu.table` rows with a socket wedge or oops a host without the
worker, so they skip unless `/proc/kallsyms` lists `lunatik_flush`, which only the fixed core exports.
The `collected.sh` rows and the `stop()` rows run on any build: the former fail rather than hang when
the wait runs out, the latter are unchanged behaviour.

"Within the bound" is a poll of `/sys/module/<m>/refcnt` for a few seconds, the way `orphan.sh`
waits on the kernel's own timers, since the close runs on a worker after the script's body returned.

The dmesg signature a spinlock case would produce without the fix is `BUG: sleeping function called
from invalid context` on a kernel with `CONFIG_DEBUG_ATOMIC_SLEEP`, and `BUG: scheduling while
atomic` on one without; `check_dmesg` matches `BUG:` on both. A hung task under RTNL is reported by
`khungtaskd` only after `hung_task_timeout_secs`, which is why the wedging rows skip rather than
assert an absence.

## Discrimination

Each refusal is proved by its message on a build that carries it. Each deferral is proved by the
callback returning and the use count returning afterwards, on a build that carries it; the same case
on a build without it is the hang the skip prevents, and is not run.

