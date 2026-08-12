# LSM binding through eBPF

Working documents for `lualsm`: reaching the Linux Security Module surface from Lua, by way of eBPF.
Both regimes the LSM offers are in scope — **observing** security relevant operations (exec,
credential changes, socket use, module loading, ptrace) and, on the hooks that allow it, **refusing**
them.

They exist so that a new contributor, with or without an AI coding assistant, can pick the work up
without first discovering that an out-of-tree module cannot be an LSM.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, gap analysis, phases, sizing, non goals, definition of done |
| [api.md](api.md) | Proposed Lua API for the `lsm` and `cgroup` modules, with worked examples |
| [kernel-notes.md](kernel-notes.md) | Verified kernel API reference: why eBPF, the kfunc contract, attach rules, config and boot requirements |
| [testing.md](testing.md) | Test strategy, the boot-dependent skip logic, and the test matrix |

Start with `plan.md`. Read `kernel-notes.md` before writing any C — in particular the first section,
which explains why this project is built on eBPF rather than on a security module of our own.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch. If you use an AI assistant, point it at that file and at `kernel-notes.md`.

Three things decide whether this work goes well:

1. **The LSM framework is closed to loadable modules.** `security_add_hooks()` is `__init` and
   unexported, and since 6.12 the hook calls are static calls sized at build time. There is no
   `lunatik_lsm.ko` that registers hooks. eBPF is the supported way in, and this project rides the
   kfunc bridge Lunatik already uses for XDP and TC.
2. **The bridge already exists — extend it, do not fork it.** `bpf_luaxdp_run` in `lib/luaxdp.c` is
   the pattern; `lunatik_ebpf.h` on `sneaky-potato/gsoc26` generalizes it; issue #561 tracks making it
   a real API. `lualsm` should be its third consumer, not a fourth copy.
3. **BPF LSM is off on most distributions.** It needs `bpf` in the kernel's `lsm=` list. Ubuntu does
   not ship it that way; Fedora does. Everything here must detect that and skip rather than fail —
   and the phase order is chosen so that useful work lands before anyone has to reboot.

## Status

These documents describe the design; they do not track progress. What is in flight, and how far along
each phase is, lives on the [LSM through eBPF board](https://github.com/orgs/luainkernel/projects/3).
Each phase is an issue there and lands as its own pull request.

