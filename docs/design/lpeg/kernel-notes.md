# Kernel notes: LPeg binding

Reference sheet for the `lpeg` binding. Everything below was checked firsthand against the vendored
Lua in this repository (`lua/`, version 5.5.0) and LPeg 1.1.0 source (upstream
`roberto-ieru/LPeg`). Re-check on the LPeg version you actually vendor and the kernel you build for.

Unlike the other project notes, most of the "kernel API" here is not the Linux kernel — it is the Lua
C API and LPeg's own internals, because the work is porting a userspace C library into the kernel Lua
state rather than calling kernel subsystems. LPeg touches no Linux kernel API directly; it allocates
only through the Lua allocator and computes.

## Licensing

LPeg is **MIT** ("Copyright 2007-2023, Lua.org & PUC-Rio", `lptypes.h:3`, license in `lpeg.html`) —
the same license as Lua, GPL-compatible, and compatible with Lunatik's `MIT OR GPL-2.0-only`. No
licensing blocker.

Vendoring rule: the upstream `.c`/`.h` files keep their **own** copyright header, unchanged. Do not
stamp them with the Lunatik/Ring Zero header — they are third-party code, and the header is how a
reviewer and a future updater tell vendored code from ours. Only `lib/lualpeg.c` (the glue) carries the
Lunatik header. Record the imported LPeg version somewhere durable (a line in the glue file or a
`lib/lpeg/VERSION`), so the copy can be refreshed against upstream later.

## Lua 5.5 compatibility — verified present

The vendored Lua is 5.5.0 (`LUA_VERSION_NUM == 505`, `lua/lua.h`). LPeg 1.1.0 advertises Lua 5.1–5.4,
but its Lua 5.1-only code is behind `#if LUA_VERSION_NUM == 501` (`lptypes.h:28`) — `lua_getfenv`,
`lua_setfenv`, `lua_objlen`, `lua_equal`, `luaL_register` are never reached on the 5.5 path. The
symbols LPeg uses on its modern path were each checked against `lua/lua.h` and `lua/lauxlib.h` and are
all present:

    lua_newuserdata      -> #define lua_newuserdata(L,s) lua_newuserdatauv(L,s,1)   (lua.h:455)
    lua_getuservalue     -> #define over lua_getiuservalue
    lua_setuservalue     -> #define over lua_setiuservalue
    lua_rawgeti, lua_geti, lua_rawlen, lua_compare                                  (present)
    luaL_newlib, luaL_setfuncs, luaL_testudata, luaL_buffinit, luaL_addchar,
    luaL_pushresult, luaL_checkinteger, luaL_optinteger, luaL_checklstring          (present)

So the C API surface is satisfied. What inspection cannot rule out is 5.4→5.5 **semantic** drift.
Therefore phase 0's real deliverable is a **clean compile plus a trivial passing match**, not a
reading — treat any build error as expected work, not a surprise. `LUA_COMPAT_GLOBAL` is on in the
vendored `luaconf.h`; the deprecated math-lib compat is off (irrelevant to LPeg).

## The library entry point already fits Lunatik

Upstream `luaopen_lpeg` (`lptree.c:1361`) builds the module with `luaL_newlib(L, pattreg)` over the
`pattreg` table (`lptree.c:1320`: `match`, `P`, `S`, `R`, `C`, `Ct`, …) and sets the backtrack-stack
cap in the registry (`lua_setfield(L, LUA_REGISTRYINDEX, MAXSTACKIDX)`, `lptree.c:1364`). That is
exactly the shape a Lunatik opener wraps; the glue is `LUNATIK_NEWLIB`-thin.

## The C-stack budget — the load-bearing constraint

LPeg's matcher puts fixed arrays on the C stack, in one frame:

* `Stack stackbase[INITBACK]` at `lpvm.c:232`, with `INITBACK = MAXBACK` (`lpvm.c:17`) and
  `MAXBACK = 400` (`lptypes.h:53`). `struct Stack` is `{const char *s; const Instruction *p; int
  caplevel}` = 24 bytes on 64-bit → **9,600 bytes**.
* `Capture capture[INITCAPSIZE]` with `INITCAPSIZE = 32` (`lptypes.h:65`), 8 bytes each → 256 bytes.

≈ 9.9 KB in a single frame, before callees, on a kernel stack that is **16 KB** total (`THREAD_SIZE`)
and shared with whatever called into Lua. In softirq that is dangerous.

Both limits are `#if !defined(...)` overridable (`lptypes.h:52`, `lpvm.c:16`). Build with small values:

    ccflags-y += -DMAXBACK=32 -DINITBACK=32 -DMAXRECLEVEL=40

The excess backtrack depth then spills to a **Lua-allocated** stack — `doublestack` (`lpvm.c:133`)
uses `lua_newuserdata`, and the depth is capped at the registry `MAXSTACKIDX` value, raising
`"backtrack stack overflow"` (`lpvm.c:129`) rather than smashing the kernel stack. So shrinking the
on-stack array trades a few hundred bytes of frame for a heap allocation on deep patterns, which is the
correct trade in the kernel. Pick the exact numbers in phase 0 and validate the spill in phase 3.

## Allocation — all through the Lua allocator

There is no raw `malloc`/`free`/`realloc` in LPeg. Every allocation goes through the Lua allocator or
`lua_newuserdata`:

* bytecode: `realloccode`/`freecode` fetch `lua_getallocf` and call it (`lpcode.c:420-431, 457`);
* backtrack-stack growth: `doublestack` → `lua_newuserdata` (`lpvm.c:133`);
* capture-list growth: `growcap` → `lua_newuserdata` (`lpvm.c:109`);
* trees/charsets/patterns: `lua_newuserdata` (`lptree.c`).

Consequence: LPeg inherits the `GFP_` context of the Lunatik runtime automatically. In a process
runtime that is `GFP_KERNEL`; in a softirq runtime it is `GFP_ATOMIC`. This is exactly the property we
want — no allocator to port — but it means a pattern whose match needs to grow the backtrack/capture
stack in softirq is doing a `GFP_ATOMIC` allocation, which can fail under pressure and must be handled
as a clean match error, not a crash. Keeping patterns shallow (so they never grow past the on-stack
arrays) avoids it entirely.

## Lazy compilation — why an explicit compile step

`lp_match` compiles on demand: `code = (p->code != NULL) ? p->code : prepcompile(L, p, 1)`
(`lptree.c:1229`). Compilation (`lpcode.c` `codegen` and the analysis passes) is **C-recursive over the
pattern tree**, bounded only by tree size (`MAXPATTSIZE ≈ 32k`, `lptypes.h`), and allocates. It must
run in a process runtime.

Because compilation is lazy, "where the first match runs" decides "where compilation runs". If a
softirq hook matches an uncompiled pattern, it compiles in softirq — recursion and `GFP_ATOMIC`
allocation in atomic context. The binding must prevent that: expose `lpeg.compile(patt)` (calls
`prepcompile` now, in process context) — see `api.md` — and make a softirq match of an uncompiled
pattern raise rather than compile.

## Matching VM — not C-recursive

`match()` (`lpvm.c:241`) is a single `for (;;)` over opcodes with `goto fail`, pushing calls and
choices onto the explicit `Stack` array (`ICall`/`IChoice`/`IRet`). It does not recurse in C, so match
depth is bounded by the (now heap-backed) stack, not the C stack. Good — the only C recursion in the
whole match path is capture extraction.

## Capture extraction — bounded C recursion

`pushcapture`/`pushnestedvalues` recurse, bounded by `MAXRECLEVEL = 200` (`lpcap.c:498`, checked at
`:510`). 200-deep C frames on top of the match frame is a kernel-stack risk; reduce it with
`-DMAXRECLEVEL` (40 is generous for the parsing this binding targets) and avoid pathologically nested
captures. This runs only when a match with captures succeeds, not on the scanning hot path.

## Backtracking cost — a CPU-DoS note, not a stack note

PEG matching with `*`/`+` and ordered choice has no memoization and can be super-linear (quadratic, and
constructed-case exponential) in subject length. Both target use cases take attacker-controlled input,
so a badly written pattern is a softirq-time CPU DoS. The stack cap protects the stack, **not** CPU
time. Mitigation is authorship, not a knob: patterns must be linear by construction, and LPeg's own
optimizer helps (`getfirst`/`ITestChar`/`ISpan` turn many idioms into non-backtracking scans). Say
this in the docs; it is the one hazard a build flag does not fix.

## What to drop or stub

* **`lpprint.c`** — debug printers (`printtree`, `printcode`), all `stdio.h`/`printf`. Drop it from the
  Kbuild objects entirely and stub its two callable exports (`lp_print*`) if anything references them;
  the VM's own `printf` calls are behind `#if defined(DEBUG)` (`lpvm.c:242-248`) and never compiled.
* **`lp_locale`** in `lptree.c:1305` — the only `ctype.h` user (`isalnum`/`isalpha`/…), implementing
  `lpeg.locale()`. Drop the entry from `pattreg` (`lptree.c:1338`), or back it with the kernel's own
  `_ctype[]` table if the feature is wanted. Not a match-path dependency.

After those two, the remaining libc surface is `string.h` (memcpy/memset/memcmp — in kernel),
`limits.h` (in kernel), and `assert.h` (compiles out with `-DNDEBUG`). No FPU: LPeg is integer-only
save one comment, matching Lunatik's integers-only invariant.

## Packaging

Mirror `luacrypto` (multi-`.c` module). Vendored sources under `lib/lpeg/`, glue in `lib/lualpeg.c`:

    obj-$(CONFIG_LUNATIK_LPEG) += lualpeg.o
    lualpeg-objs := lualpeg.o lpeg/lpvm.o lpeg/lpcap.o lpeg/lpcode.o \
                    lpeg/lpcset.o lpeg/lptree.o

Confirm in phase 0 that Kbuild resolves objects in a subdirectory (it does for out-of-tree modules
with the relative path as above); if it fights, fall back to flat `lib/lp_*.c` names, but prefer the
subdir so the vendored files keep their upstream names and stay diffable. `re.lua` installs like any
`lib/*.lua` to `/lib/modules/lua/`.

`ccflags-y` for the module carries the `-D` limits above plus `-DNDEBUG`, and the include path for the
vendored headers.

## Summary of the verified facts

| Fact | Where | Consequence |
|------|-------|-------------|
| Lua 5.5 exports LPeg's ≥5.2 API surface | `lua/lua.h`, `lua/lauxlib.h` | build is plausible; confirm by compiling |
| 9.6 KB `Stack` array on the C stack per match | `lpvm.c:232`, `lptypes.h:53` | `-DMAXBACK`/`-DINITBACK` small; validate spill |
| all heap via Lua allocator | `lpcode.c:420`, `lpvm.c:109,133` | inherits `GFP_`; atomic-safe if shallow |
| lazy compile on first match | `lptree.c:1229` | need `lpeg.compile`; softirq must not compile |
| match VM is a stack machine, not C recursion | `lpvm.c:241` | match depth bounded by heap stack |
| capture recursion bounded at 200 | `lpcap.c:498` | `-DMAXRECLEVEL` small |
| MIT license, upstream copyright | `lptypes.h:3` | vendor verbatim; keep headers |
| `stdio.h` only in `lpprint.c`; `ctype.h` only in `lp_locale` | grep | drop/stub both |

