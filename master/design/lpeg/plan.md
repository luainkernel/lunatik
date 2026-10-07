# Plan: LPeg binding

Execution plan for the `lpeg` binding.

## Expected results

1. A kernel Lua script can build LPeg patterns with the full combinator API (`P`, `R`, `S`, `C`,
   `Ct`, grammars, …) and match them against a Lua string, with captures.
2. The `re` module is available, so patterns can be written in LPeg's grammar-string syntax
   (`re.compile`, `re.match`), not only combinators.
3. Patterns match against a `data` object (packet payload / arbitrary buffer) with no copy, not only
   Lua strings, so hooks can parse packet bytes directly.
4. A pattern compiled in a process runtime can be matched from a non-sleepable (softirq) runtime
   safely — bounded C stack, atomic-context allocation — or, if that proves unsafe, matching is
   cleanly restricted to process context with a documented reason.
5. An example plus a KTAP suite: an HTTP request-line and `Host` parser written as an LPeg grammar,
   proving structured field extraction in kernel Lua.

## Where we are today

The kernel Lua state ships the standard string library (`lua/lstrlib.c`), so `string.match` and Lua
patterns are available — enough for a single anchored capture (`string.match(payload, "\r\nHost:
([^\r\n]+)")`, as the conntrack L7 example does), but not for a real grammar: no ordered choice, no
recursion, no composable rules, no typed captures. There is no PEG engine.

A sweep of every local and remote branch, and of the closed issues and pull requests, found no LPeg
code anywhere in the tree; LPeg appears only in old GSoC idea pages under `lablua`. This is a clean
slate.

What the base *does* give this project, verified:

* the vendored Lua is **5.5.0** (`lua/lua.h`), and it already exports every C API symbol LPeg uses on
  its Lua ≥ 5.2 path (see `kernel-notes.md` for the checked list);
* `luacrypto` is a multi-`.c` module (`luacrypto-objs := …` in `lib/Kbuild`), so a multi-file
  vendored library packages the same way;
* `lib/*.lua` files install to `/lib/modules/lua/`, so `re.lua` ships as-is with no porting.

## What is missing

| Expected result | Gap |
|-----------------|-----|
| Combinator API in kernel Lua | LPeg's C is not built or loadable; no `lpeg` module. |
| `re` grammar syntax | `re.lua` not installed, and it depends on `lpeg` being loadable first. |
| Match a `data` object | `lp_match` takes a Lua string via `luaL_checklstring`; it has no path for a `data` object's buffer. |
| Softirq matching | Untested; LPeg's on-C-stack arrays and lazy first-match compilation are unsafe in softirq as shipped. |
| Example and tests | No suite, and no HTTP-parse example. |

Supporting gaps:

* the vendored sources include a debug printer (`lpprint.c`, `stdio.h`) and a locale feature
  (`lp_locale` in `lptree.c`, `ctype.h`) that do not belong in the kernel;
* the default `MAXBACK`/`INITBACK`/`MAXRECLEVEL` are sized for userspace, not a 16 KB kernel stack;
* compilation is lazy (on first match), which would put pattern compilation in whatever context the
  first match runs in — softirq, if a hook matches first.

## Shape of the work

One new kernel module, `lpeg` (`lib/lualpeg.c` glue plus the vendored LPeg C under `lib/lpeg/`), and
one installed Lua file (`re.lua`). The module registers the `lpeg` library exactly as upstream's
`luaopen_lpeg` already does (`luaL_newlib` over `pattreg`), wrapped in Lunatik's opener.

The full API proposal is in `api.md`; the constraints that drive it are in `kernel-notes.md`. The one
fact that shapes the whole project:

> LPeg's matcher is not the risk — its C-stack use and its lazy compilation are. It puts ~9.6 KB of
> arrays in a single stack frame per match (`Stack stackbase[INITBACK]`, `INITBACK = MAXBACK = 400`),
> against a 16 KB kernel stack shared with the caller, and it compiles a pattern lazily on the first
> match. So the project is not "port a regex engine"; it is "run an already-kernel-shaped engine
> safely within the kernel's stack and atomic-context limits", which means shrinking the on-stack
> arrays (`-DMAXBACK`/`-DINITBACK`), bounding capture recursion (`-DMAXRECLEVEL`), and forcing
> compilation into process context so softirq only ever *matches* a pre-compiled pattern.

The second fact worth stating up front: this vendors third-party C. The upstream files stay verbatim
and diffable (upstream names and copyright), so the copy can be refreshed; only `lib/lualpeg.c` is
Lunatik's. See `kernel-notes.md`.

## Phases

Each phase is one or more self-contained pull requests.

### Phase 0: vendor and build

Bring the LPeg C sources into `lib/lpeg/`, add the glue file and the Kbuild/Kconfig entries, and get
`require("lpeg")` to load in a **process** runtime with a trivial match working
(`lpeg.match(lpeg.P"a", "a")`). This phase carries the two things that de-risk everything else:

* **prove Lua 5.5 compatibility by compiling** — the API surface is present (`kernel-notes.md`), but
  5.4→5.5 semantic drift is only settled by a clean build and a passing trivial match, not by
  inspection;
* **apply the port changes**: drop `lpprint.c` from the build and stub its two callable exports; drop
  or neutralize `lp_locale` (the `ctype.h` user); compile with small `-DMAXBACK`/`-DINITBACK` and a
  reduced `-DMAXRECLEVEL`.

Deliverables: `lib/lpeg/*` (vendored, upstream headers intact), `lib/lualpeg.c`, `lib/Kbuild` +
`Kconfig` entries, `config.ld` and README module-table rows, a minimal `tests/lpeg/`.

### Phase 1: the API surface and the `re` module

Confirm the full combinator API behaves in-kernel — constructors, ordered choice, repetition,
grammars, and every capture kind (`C`, `Ct`, `Cg`, `Cc`, `Cp`, back-references, `Cmt` match-time
captures). Install `re.lua` and confirm the grammar-string front end. This is where the coverage
matrix in `testing.md` gets filled for string subjects.

Match-time captures (`Cmt`) call a Lua function *during* the match; document and test that this is
fine in a process runtime and must be non-sleeping in softirq.

### Phase 2: matching a `data` object

Let the subject of a match be a `data` object, read as `(ptr, len)` with no copy, so a hook can parse
packet bytes. `lp_match` currently insists on a Lua string; add a `data`-aware path (a Lunatik-side
`lpeg.match` wrapper, or acceptance of a `data` argument in the C entry) that feeds LPeg the buffer
directly. Decide and document the lifetime rule: the `data` must stay valid for the duration of the
match (it is, inside a hook).

### Phase 3: softirq safety

Make "compile in process, match in softirq" real and proven:

* add an explicit `lpeg.compile(patt)` (or document that a first match in process context compiles),
  so a pattern reaching a softirq hook is already compiled and softirq never runs `prepcompile`;
* validate matching from a `softirq` runtime with the shrunk stacks and atomic-context allocation,
  under real backtracking, and confirm a deep backtrack spills to the heap or errors cleanly rather
  than overflowing the kernel stack;
* if any of that cannot be made safe, restrict matching to process runtimes with a
  `lunatik_cannotsleep`-style guard and document why — an honest gate beats a machine check.

This is the risk phase; it lands after the engine is otherwise proven, so a stack overflow here is
found against a working baseline.

### Phase 4: example and documentation

An HTTP request-line + `Host` parser written as an LPeg grammar (the demonstration of expected result
5), a documentation pass, and whatever API cleanup the example exposes. The example parses a single
buffer; it explicitly does **not** reassemble TCP (that is the `stream` project) and says so, the way
the conntrack L7 example is honest about its limits.

## Sizing

Sized by what fits in a reviewable pull request.

| Scope | Phases |
|-------|--------|
| Minimum useful | 0 to 1. LPeg and `re` usable in a process runtime against Lua strings. |
| Complete | 0 to 4. Adds `data` matching, softirq safety, and the worked example. |

Phase 0 is the real gate: if the vendored code does not build cleanly against Lua 5.5, everything
after it waits on fixing that, so it is worth doing first and carefully.

## Non goals

* **Being the router.** The radix/hash routing table (L2 in the architecture) is a separate,
  pure-Lua project. This binding parses; it does not route.
* **Being the byte source.** TCP reassembly and the stream view (L0) are a separate project. The
  example matches one buffer and misses patterns spanning segment boundaries, by design.
* **Being the IDS matcher.** LPeg is a single-grammar, ordered-choice, anchored matcher; it is not a
  simultaneous multi-pattern scanner. Aho-Corasick (the next project) owns that. Do not force
  thousands of signatures into an ordered choice here.
* **Modifying LPeg's language or semantics.** Vendor it faithfully. The only edits are the kernel
  port (drop `lpprint`, neutralize `lp_locale`, size the `-D` limits, the `data` subject path). Any
  behavioural change to matching is out of scope and would break diffability against upstream.
* **JIT or SIMD.** LPeg is a portable scalar bytecode VM; that is the point. Nothing here needs FPU.

## Risks

| Risk | Mitigation |
|------|-----------|
| Lua 5.5 semantic drift breaks a clean 5.4-era build | Phase 0 compiles against the vendored tree and runs a trivial match before anything else; treat a build failure as the phase's real content, not a surprise. |
| ~9.6 KB on-C-stack arrays overflow the kernel stack in softirq | Shrink with `-DMAXBACK`/`-DINITBACK`; the overflow path already spills to the Lua-allocated stack. Prove it in phase 3 with a deep-backtrack test, not by argument. |
| Lazy compilation runs `prepcompile` in softirq on first match | Force compilation in process context (`lpeg.compile` or a warm-up match); phase 3 owns this. |
| Backtracking is super-linear on adversarial input → softirq CPU DoS | Patterns must be linear by construction; document it, and lean on LPeg's own `ITestChar`/`ISpan` optimizations. The stack cap protects the stack, not CPU time — say so. |
| Vendored copy drifts from upstream and becomes unmaintainable | Keep upstream files verbatim (names, copyright); confine all Lunatik code to `lib/lualpeg.c`; record the imported LPeg version. |
| `Cmt` match-time captures call Lua mid-match | Fine in process; in softirq the callback must not sleep. Documented and tested. |

## Definition of done, per phase

1. builds clean on the target kernel, no new warnings;
2. LDoc on the Lunatik-authored surface (the glue module and any added functions); the vendored files
   keep their upstream docs; `lpeg`/`re` listed in `config.ld` in alphabetical order;
3. a row in the README module table;
4. a test in `tests/lpeg/`, wired into that suite's `run.sh`, and described in `tests/README.md`;
5. the test skips (not fails) when a needed config is absent;
6. the full suite still passes: `sudo lunatik test`;
7. error paths audited: for every raise, whatever was acquired is released (patterns are GC-managed
   userdata, so this is mostly the glue's argument checking);
8. commits are small and each one stands alone; vendored imports are one reviewable commit, distinct
   from the Lunatik glue.

