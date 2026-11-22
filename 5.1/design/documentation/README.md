# Documentation

Working documents for the content of Lunatik's documentation: the landing README, the guide under
`doc/guide/`, the C API reference in `doc/capi.md`, the module reference the LDoc blocks in `lib/` and
`lunatik_*.c` generate, and the example READMEs. The site that renders them is settled; what it says
is what this work changes: text the code contradicts, contracts only the code states, and whole kinds
of page a reader looks for and does not find.

| Document | What it is for |
|----------|----------------|
| [audit.md](audit.md) | The audit against the code at `85d9a1c1c`: a rating per page, module and example, 206 findings with the code that proves each one and its fix, and the gaps by reader journey |
| [plan.md](plan.md) | The phases, the pull requests of each, what each closes, and the definition of done |
| [conventions.md](conventions.md) | The templates for a module page, an example README, a how-to and a tutorial; the terminology; the checks that keep the docs true to the code |

Start with `plan.md`. A pull request of this work names the audit findings it closes by identifier,
`G-03` or `MN-12`, and the phase issue it belongs to.

## Decisions

Taken with the maintainer on 2026-09-27:

1. The examples install with `sudo make install`, the one command the guide teaches, and not with
   the partial `examples_install` target AGENTS.md steers away from.
2. A netfilter hook callback that returns no verdict gets the hook's policy, `NF_ACCEPT`, as one that
   raises already does (#1237); the callback contract is documented that way.
3. A module page declares its execution context and its requirements in LDoc tags of its own
   (`custom_tags` in `config.ld`), rendered as sections on every page, provided LDoc renders them as
   expected; otherwise in a fixed paragraph. The first pull request of phase 2 settles which.
4. The explanation of runtimes, execution contexts and the object model moves to a concepts page on
   the site, and AGENTS.md points to it instead of carrying its own copy.
5. The docs define "armed", the state after a script body returns, and quote the error text
   `not allowed after module load` as it is; renaming that message is a change of its own, outside
   this work.
6. The work is tracked as an epic with one issue per phase and a GitHub Project.

## Working on this

The repository conventions in [AGENTS.md](../../../AGENTS.md) apply to every change here: a doc is
read against the code before it is written, a command in a doc is one that was run, and a claim about
the kernel is read in its source. What is particular to this work:

1. **The code is the authority.** A finding in `audit.md` cites the line that proves it at
   `85d9a1c1c`; read the line again at the current master before writing the fix, since the code may
   have moved.
2. **A defect in the code is not fixed in its doc.** Where the audit found the code wrong, the fix is
   an issue of its own (#1234, #1235, #1236, #1237, #863, #1172), and the doc describes the code once
   that fix merges.
3. **Move before you write.** Phase 3 moves text into the page that should hold it and writes nothing
   new, so its diff reads as a move; new text comes in phase 4.

