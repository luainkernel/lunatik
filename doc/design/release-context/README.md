# Release context: RTNL, locks and where a runtime closes

Working documents for the five issues that share one root: a runtime, or a socket, whose last
reference is dropped by something other than its own `stop()` closes on the task that dropped it,
and that task may hold RTNL, a spinlock, or be the one another task waits for. The issues are #1050,
#1055, #1069, #1075 and #1087; the merit review of each is in `plan.md`.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | The merit of each issue with its trace, the fact that decides the design, the shapes weighed, the impact on #1088 and #1089, and the phases |
| [api.md](api.md) | What changes at the Lua and C interfaces: the refusals, the deferred release, the documentation each one carries |
| [kernel-notes.md](kernel-notes.md) | Every kernel and Lua fact the plan rests on, linked at a pinned tag or commit, across the kernels the tree supports |
| [testing.md](testing.md) | The matrix each phase is held to, the tests that would wedge a host without their fix, and how they skip |

Start with `plan.md`. Read `kernel-notes.md` before writing any C.

## The deciding fact

> A class release runs synchronously on the task that drops the object's last reference, in whatever
> context that task is in: `lunatik_putobject` is a bare `kref_put`, and `lunatik_releaseobject`
> calls the release in place. Three of the puts that can be last are not a script's `stop()` and
> cannot refuse: the collector's, at any allocation's GC step in any Lua the task runs; an
> `rcu.table` entry's, under the table's spinlock; and a thread body's end, on the kthread. Only two
> classes have a release that sleeps or waits on a lock and can reach such a put: the runtime, whose
> `lua_close` runs every release of its state, and the socket, whose `sock_release` takes RTNL for an
> IPv4 or a packet membership on every kernel in the range. Every other sleeping release is pinned to
> `lua_close` by holding its runtime or a registry slot.

From this, a refusal answers exactly the puts a script makes by name, and nothing else can answer
the others but moving them off that task. The plan does both: the named entry points refuse under
RTNL, as `runtime:stop()` does since #1045, and a release nobody called runs on a kernel worker.

## Expected results

1. A script closes a socket, stops a thread and creates a channel from a netdevice callback and gets
   `"not allowed under RTNL"` where the kernel path would wait on the lock its task holds, and the
   call goes through everywhere else.
2. A child runtime, or a socket, dropped without a `stop()` and collected inside a netdevice callback
   closes after the callback returns, off the task that holds RTNL, and the host does not hang.
3. An `rcu.table` entry replaced or removed while holding the last reference of a runtime or a
   socket closes it in process context, never under the table's spinlock and never in softirq.
4. `runtime:stop()`, `percpu:stop()` and `lunatik_stop` stay synchronous; `lunatik reload` after a
   deferred close finds every module unloadable.
5. A KTAP suite covering the drop by the class by the context, with the cases that would wedge a
   host skipping on a build without the fix.

## Working on this

The repository conventions that apply to every change here are in
[AGENTS.md](../../../AGENTS.md). Three of them matter more than the rest for this work:

1. **These are hangs.** No experiment on a shared host reaches an RTNL self-deadlock, a sleeping
   call under a spinlock or a lost wakeup: the paths are traced by reading, and a test that would
   hang a host without its fix skips unless the loaded module carries the fix.
2. **A guard keys on a property true by construction.** The socket's refusal reads the same list
   the kernel's release reads; the deferral is unconditional for the class that declares it, not
   keyed on `in_atomic()`, which the kernel says not to trust, nor on the one lock the core knows.
3. **A decision taken with the maintainer is not reversed alone.** `runtime:stop()` refusing under
   RTNL (#1045), a hook holding its runtime (#1042, #1077) and a runtime closing when its last handle
   is collected (`tests/runtime/collected.sh`) are contracts the plan keeps.

## Status

These documents describe the design; they do not track progress. What is in flight lives on the
[release context board](https://github.com/orgs/luainkernel/projects/7). Each phase is an issue
there and lands as its own pull request.

