# Conntrack and NAT support

Working documents for the conntrack and NAT binding, initially proposed on the
[LabLua GSoC ideas page](https://github.com/labluapucrio/gsoc/blob/main/2026/ideas.md#conntrack-and-nat-support-for-lunatik)
and now tracked here as a regular project. They exist so that a new contributor, with or without an AI
coding assistant, can pick the work up without reverse engineering the netfilter internals first.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, gap analysis, phases, non goals, definition of done |
| [api.md](api.md) | Proposed Lua API for the `conntrack` and `nat` modules, with a worked example |
| [kernel-notes.md](kernel-notes.md) | Verified kernel API reference: symbols, signatures, context rules, config dependencies |
| [testing.md](testing.md) | Test strategy, the namespace harness the suite needs, and the test matrix |

Start with `plan.md`. Read `kernel-notes.md` before writing any C.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch. If you use an AI assistant, point it at that file and at `kernel-notes.md`.

Two habits matter more than anything else in this project:

1. **Verify kernel APIs against the kernel you are building for.** Netfilter internals move. Several
   signatures quoted in `kernel-notes.md` changed within the 6.x series. Check the headers under
   `/usr/src/linux-headers-$(uname -r)/include` and confirm exports in `Module.symvers` before
   assuming a function exists or takes the arguments you remember.
2. **Know which context your code runs in.** Registration is process context; hooks are softirq. A
   sleeping call reached from a hook does not return an error, it wedges the machine.

## Status

These documents describe the design; they do not track progress. What is in flight, and how far along
each phase is, lives on the [conntrack and NAT board](https://github.com/orgs/luainkernel/projects/1).
Each phase is an issue there and lands as its own pull request.

