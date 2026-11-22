# LPeg binding

Working documents for `lpeg`: bringing Roberto Ierusalimschy's
[LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/) — Parsing Expression Grammars for Lua — into the
kernel Lua state, so kernel scripts can parse and match structured input (protocol headers, HTTP
request lines, config, byte formats) with a real grammar engine and captures, instead of hand-rolled
byte walking or the limited Lua pattern library.

This is the parsing/matching **primitive**, not an application. It is the first of a small family of
matching-layer projects; the Aho-Corasick multi-pattern module and the radix router are separate. An
HTTP parser ships here only as the *demonstration* of the engine, not as a gateway.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, gap analysis, phases, non goals, risks, definition of done |
| [api.md](api.md) | The Lua API (`lpeg` combinators, the `re` grammar-string module), matching a `data` object, the compile/match discipline, worked examples |
| [kernel-notes.md](kernel-notes.md) | Verified facts: Lua 5.5 API compatibility, the C-stack budget, allocation context, lazy compilation, licensing, what to drop/stub, packaging |
| [testing.md](testing.md) | Test strategy and the coverage matrix |

Start with `plan.md`. Read `kernel-notes.md` before writing or vendoring any C.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch. If you use an AI assistant, point it at that file and at `kernel-notes.md`.

What is unusual about this project, and what to keep in mind:

1. **This vendors third-party C.** Unlike every other Lunatik module, most of the code is upstream
   LPeg, copied in verbatim. Keep the upstream files diffable against their origin (upstream names,
   upstream copyright headers — do not stamp them with the Lunatik header), so the vendored copy can be
   updated later. Only the thin glue file is Lunatik's.
2. **The risk is the kernel C stack, not the matcher.** LPeg is already kernel-shaped — every
   allocation goes through the Lua allocator and the matching VM is an explicit stack machine, not C
   recursion. The one real hazard is that it puts ~9.6 KB of arrays on the C stack per match, against a
   16 KB kernel stack, and that patterns compile lazily on first match. `kernel-notes.md` is mostly
   about taming those two facts.
3. **Compile in process context, match anywhere (carefully).** Pattern compilation allocates and
   recurses over the pattern tree; do it from a process runtime, never per-packet in softirq.

## Status

These documents describe the design; they do not track progress. What is in flight, and how far along
each phase is, lives on the [LPeg binding board](https://github.com/orgs/luainkernel/projects/4). Each
phase is an issue there and lands as its own pull request.

