# Bytecode compiler for Lunatik

Working documents for `lunatikc`: a userspace compiler that turns kernel Lua scripts into precompiled
binary chunks the in-kernel Lua accepts, including cross-compiling on a development host for a
different target (32-bit, other endianness), so that scripts can ship as bytecode — no parser pass at
load time, no source on the device, smaller files, and a path to a kernel build without the compiler
front end at all.

They exist so that a new contributor, with or without an AI coding assistant, can pick the work up
without first rediscovering why the distribution `luac` does not work here.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, what is missing, the incremental phases, non goals, risks, definition of done |
| [api.md](api.md) | The tool's command line, the build and install hooks, and what (little) changes on the kernel side |
| [kernel-notes.md](kernel-notes.md) | Verified reference: the kernel Lua fork's bytecode format, what makes stock `luac` incompatible, what is endianness-dependent, how loading already works in the kernel, bytecode trust |
| [testing.md](testing.md) | Test strategy — a `luac` KTAP suite compiling on the host and running in the kernel, plus the harness pitfall with stripped chunks |

Start with `plan.md`. Read `kernel-notes.md` before touching `lunatik_conf.h` or the `lua/` submodule.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch.

Three facts shape everything here, and are worth carrying from the start:

1. **The kernel already loads bytecode.** Every in-kernel file load goes through `lunatik_loadfile`
   with mode `NULL` (`"bt"`), and `lua_load` detects a binary chunk by its first byte. Nothing on the
   kernel side has to change for a correctly built chunk to run; the whole problem is producing one.
2. **Stock `luac` cannot produce one.** The kernel Lua is an integer-only fork: under `_KERNEL` the
   opcode enum drops the float opcodes (so every opcode after `OP_LOADI` is renumbered), `/` compiles
   to integer division, and `lua_Number` is `lua_Integer`, which the bytecode header checks. The
   compiler must be built from the same `lua/` sources with the same `_KERNEL` configuration, on the
   host. This is the only correct way to get an identical front end; a reimplementation is not.
3. **Cross-endian is the only real cross-compilation problem.** Sizes in a Lua 5.5 chunk are
   endian-independent varints and `lua_Integer` is 8 bytes on every Lunatik target, 32-bit included.
   Only the raw instruction vector, the absolute line table and the header probes carry the
   host's byte order, so a host that matches the target's endianness produces a valid chunk with no
   special handling, and a byte-swapping dump (a change in the `lua/` fork) covers the rest.

## Status

Design notes plus a prototype on the `claude_luac` branch (on top of `origin/master`): the compiler,
its build and install wiring, `BYTECODE=1`, the `luac` suite and the `runner.lua` trim fix — phases
1–3 of `plan.md`, full suite green with source and with bytecode installs. Cross-endian (phase 4)
and the follow-ups are not started. Not yet an epic; the phases are sized to become one issue each.

