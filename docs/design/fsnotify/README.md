# Filesystem notification and permission binding

Working documents for the `fsnotify` binding: a Lua interface to the kernel's filesystem
notification subsystem, covering both regimes it offers — asynchronous notification (what `inotify`
and `fanotify` expose to userspace) and synchronous **permission events**, where the handler's answer
decides whether the access happens.

They exist so that a new contributor, with or without an AI coding assistant, can pick the work up
without reverse engineering `fs/notify/` first.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, gap analysis, phases, sizing, non goals, definition of done |
| [api.md](api.md) | Proposed Lua API for the `fsnotify` module, with worked examples |
| [kernel-notes.md](kernel-notes.md) | Verified kernel API reference: symbols, signatures, context rules, version drift |
| [testing.md](testing.md) | Test strategy and the test matrix |

Start with `plan.md`. Read `kernel-notes.md` before writing any C.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch. If you use an AI assistant, point it at that file and at `kernel-notes.md`.

Three habits matter more than anything else in this project:

1. **Verify kernel APIs against the kernel you are building for.** `fs/notify/` has been reworked
   repeatedly. `fsnotify_add_mark` alone changed its second parameter between 6.8 and 6.15, and the
   permission event path changed again in 6.14. Check the headers under
   `/usr/src/linux-headers-$(uname -r)/include` and confirm exports in `Module.symvers`.
2. **Respect reentrancy.** A handler runs inside the syscall of the process being watched. If the
   handler itself touches a watched file, it re-enters. This is not a corner case to fix later; it is
   the first thing the design has to answer. See `api.md`.
3. **A denied `open` is a wedged machine when you deny the wrong file.** Test permission rules on a
   scratch directory, never on `/` or on `/lib/modules/lua`.

## Status

These documents describe the design; they do not track progress. What is in flight, and how far along
each phase is, lives on the [fsnotify board](https://github.com/orgs/luainkernel/projects/2). Each
phase is an issue there and lands as its own pull request.

