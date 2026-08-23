# Plan: bytecode compiler for Lunatik

Execution plan for `lunatikc`, the userspace compiler and cross-compiler for kernel Lua scripts.
Built incrementally: each phase is a shippable pull request, and the first one is the whole
user-visible feature. Phases 1–3 are prototyped on the `claude_luac` branch (four commits on top of
`origin/master`, full suite green with source and with bytecode installs); this plan was revised
against that prototype.

## Expected results

1. `lunatikc script.lua` on a development host produces a binary chunk that the kernel Lua loads
   and runs, with the same semantics as the source (integer-only arithmetic, `/` as integer
   division), optionally stripped of debug information.
2. Installing compiled chunks is a build option: `make install` can ship the kernel-side Lua
   libraries (`lib/lunatik/*.lua`, `lib/*.lua`, …) and examples as bytecode instead of source, with
   the test suite passing either way.
3. A chunk compiled on a 64-bit host runs on a 32-bit little-endian target unchanged, and a big-endian
   target is reachable through a byte-order option — a real cross-compiler for the OpenWrt
   targets Lunatik is deployed on.
4. A `luac` KTAP suite that compiles on the host and runs in the kernel, covering the happy path,
   strip, and rejection of foreign chunks.
5. Follow-ups that become possible once bytecode is first class: a kernel build without the
   parser, zero-copy loading of resident chunks (`'B'` mode), encrypted bytecode through `darken`.

## Where we are today

* The kernel already accepts binary chunks everywhere (`lunatik_loadfile` mode `NULL` = `"bt"`,
  also used by `require`); `ldump.o` and `lundump.o` are in `lunatik.ko`; `string.dump` exists.
  Nothing in the tree exercises it — no test, doc, issue or branch mentions bytecode.
* There is no way to produce a chunk. `lua/` ships no `luac.c`, the `Makefile` builds no host
  tool (the host `lua5.4` is only used for `autogen.lua` and LDoc), and the distribution `luac`
  is incompatible with the kernel fork (`kernel-notes.md`): different opcode numbering, `/`
  semantics, no floats, integer `lua_Number` in the header. Verified: a stock 5.5 chunk fails with
  `bad binary format (Lua number format mismatch)`.
* `lunatik_conf.h` mixes the number configuration the compiler must share (`LUA_NUMBER =
  LUA_INTEGER`, …) with kernel-only material (`printk`, `<linux/module.h>`, `lunatik_loadfile`,
  the `LUA_EXTRASPACE` struct), so it cannot be included by a host build as is.
* Verified on the prototype: the Lua core (`lapi … lzio`, `lauxlib`) built on the host with
  `-D_KERNEL -DLUA_USE_LINUX` and the shared part of `lunatik_conf.h` yields a ~200 KB static
  compiler whose chunks, installed under `/lib/modules/lua/<name>.lua`, run in the kernel, full and
  stripped. With every kernel Lua library and example installed as stripped chunks (`BYTECODE=1`),
  the whole suite passes (117/117, 6.8.0-136 aarch64), `driver.lua` included — so `lunatik_run`
  loads a chunk at `modprobe` time too. The kernel libraries shrink from 12.8 KB of source to
  4.0 KB of stripped bytecode.
* Found by the suite: `runner.lua`'s `trim()` used `gsub("(%w+).lua", "%1")`, where the dot
  matches any character, so any script path with a word, a character and `lua` in it was mangled
  (`tests/luac/x` → `testsc/x`). Fixed on the branch (`trim` now drops only a trailing `.lua`); a
  prerequisite for a suite named `luac`, and a latent bug for any such path.

## What is missing

1. A host-buildable `lunatik_conf.h`: fence the kernel-only parts with `#ifdef __KERNEL__`, keep
   the number configuration and limits shared. One header, one source of truth — no shim copy.
2. The tool itself: a small C driver (`luaL_loadbufferx` text-only + `lua_dump`), with `-s`,
   `-o`, a chunk name option, and multiple inputs; built from the `lua/` core with host `cc`.
3. Build and install wiring: a `lunatikc` Makefile target, installed next to `bin/lunatik`; an
   opt-in `BYTECODE=1` for `scripts_install`/`examples_install` that compiles instead of copies.
4. Tests and docs: `tests/luac/`, `tests/README.md`, README usage section, and the `check_dmesg`
   fix for stripped chunks (`testing.md`; `run_script` already fails on any output upstream).
5. Cross-endian: a dump-side byte swap in the `lua/` fork, behind a host-only define, with a
   `-e big|little` option (and a `-B`-mode loader, a parser-less kernel, `darken` bytecode as
   separate follow-ups).

## Shape of the work

**Host tool, not kernel feature.** The kernel side is already done; resist the temptation to "add
bytecode support" in C. The only kernel-visible change in phase 1 is the `__KERNEL__` fence in
`lunatik_conf.h`, which is a no-op for the kernel build (same macros, same values).

**Same front end, by construction.** The compiler links the very `lua/` sources `lunatik.ko` is
built from, with the same `_KERNEL` define. Bumping the submodule rebuilds both. This is what makes
"bytecode the kernel accepts" a tautology rather than a maintenance burden; do not fork `ldump.c`
into the tool.

**Install bytecode under the `.lua` name.** `lunatik run <name>` and `require` append `.lua` in
the kernel (`lunatik_core.c:219`, `package.path`); `lua_load` sniffs the signature byte. Keeping
the name means zero changes to the runner, the CLI, `package.path`, and every `SCRIPT=` in the
tests. A `.luac` suffix buys nothing and costs a kernel change plus a second search path.

**Text-only on the host.** The tool parses with mode `"t"`, so it never re-emits a chunk it did not
compile; a foreign `.luac` fed by mistake is a parse error, not a silently copied incompatibility.

## Phases

### Phase 1 — the compiler (`bin/lunatikc.c`, `lunatik_conf.h`, `Makefile`) — prototyped

* `lunatik_conf.h`: fence kernel-only parts with `#ifdef __KERNEL__`. Shared on both sides:
  `LUAI_UACNUMBER`, `LUA_NUMBER`, `LUA_NUMBER_FMT`, `l_randomizePivot`, `LUAL_BUFFERSIZE`,
  `LUAI_MAXSTACK`, `LUNATIK_GCCOUNT`, `lua_getlocaledecpoint` (so the host parser ignores the
  locale). Kernel only: `<linux/random.h>` / `luai_makeseed`, `lua_write*`, `l_signalT`, `panic`,
  `<linux/module.h>` and `lsys_*`, `lunatik_loadfile`/`luaL_loadfilex`, `LUA_ROOT`/`LUA_PATH_DEFAULT`,
  `lunatik_runtime_t`/`LUA_EXTRASPACE`, `luaS_hash`, the `current` undef.
* `bin/lunatikc.c`: `lunatikc [-s] [-o out] [-n chunkname] in.lua…`. Reads the file, parses with
  `"t"`, `lua_dump` with `strip`; writer tolerates empty blocks; default output `<in>.luac` next to
  the input (`-o` is a directory when there are several inputs), default chunk name `@<in>` (so
  errors point at the source the developer edits, and `-n` lets an installer set
  `@/lib/modules/lua/<name>.lua`). Exit non-zero on any error, message on stderr. ~160 lines.
* `Makefile`: `lunatikc` target compiling `bin/lunatikc.c` plus the `lua/` core list (no
  `lbaselib`/`loadlib`/`linit`/`liolib`) with `$(HOSTCC)` `-std=gnu99 -O2 -D_KERNEL
  -DLUA_USE_LINUX -I. -Ilua`; part of `all`; `clean` removes it; `scripts_install` installs it to
  `LUNATIK_INSTALL_PATH` next to `lunatik`; `scripts_uninstall` removes it.
* One commit for the header fence (no behavior change: same `lunatik.ko` text size with and
  without it), one for the tool and its wiring, docs in the same commit (README usage section).
  The `-Wall` host build shows one warning from the fork (`llex.c`: `expo` set but unused under
  `_KERNEL`); a one-line fix in `luainkernel/lua`, not in this tree.

### Phase 2 — the `luac` test suite (`tests/luac/`, `tests/lib.sh`, `lib/lunatik/runner.lua`) — prototyped

* `tests/luac/run.sh`: compile the installed test scripts on the host with
  `lunatikc` into `/lib/modules/lua/tests/luac/`, run it with `lunatik run`, assert the expected
  `dmesg` line; repeat with `-s`; assert that a stock-format chunk (a crafted header with a
  double `LUAC_NUM`) is rejected with `Lua number format mismatch`; assert a text-only wrapper
  still works (`load(chunk, name, "t")` inside the kernel rejects the binary).
* `tests/lib.sh`: `check_dmesg` recognises errors by `\.lua:[0-9]+:`; a stripped chunk errors as
  `?:?:`. Extend the pattern so stripped failures do not pass silently (`testing.md`).
* `lib/lunatik/runner.lua`: the `trim()` fix above, as its own commit (a bug on its own).
* Register in `tests/run.sh`, `tests/README.md`, README `### Testing`.

### Phase 3 — installing bytecode (`Makefile`) — prototyped, folded into phase 1

* `BYTECODE=1 make install`: an `INSTALL_LUA` recipe macro that is `install -m 0644` by default
  and `lunatikc -s -o <dest>/<name>` with `BYTECODE=1`; every `.lua` install line in
  `scripts_install` and `examples_install` goes through it, so the list of files stays in one
  place. Two exceptions stay source: `autogen/lunatik/config.lua` (symlinked into the host
  `package.path` and read by the `lunatik` CLI under the host Lua 5.4) and the tests (the suite
  compiles its own). `-n` is moot with `-s` (no source name is kept).
* Default stays source. It came out at 15 Makefile lines, so it shipped with the tool rather than as
  a separate phase; the full suite was run both ways.

### Phase 4 — cross-endian (`lua/` fork, `bin/lunatikc.c`) — prototyped

* A `lunatik_conf.h`-only route was investigated first and does not exist cleanly: `dumpVector`
  and `dumpBlock` are file-local to `ldump.c`, defined after every include, so no configuration
  header can reach them; the luaconf hooks that do expand inside the dump path (`lua_lock`,
  `lua_assert`) carry no block-type context (strings must not be swapped) and are used in other
  scopes; and swapping in the tool's writer or as a post-process would re-encode the whole chunk
  grammar in `lunatikc.c` — a shadow of `lundump.c`. Upstream's own comment says where the change
  belongs: "All high-level dumps go through dumpVector; you can change it to change the endianness
  of the result".
* So: branch `claude_luac` in `luainkernel/lua`, guarded by `LUNATIKC` (defined only by the tool
  build; the kernel and stock builds are untouched). `dumpVector` honors a `luaU_dumpswap` flag
  and routes raw elements through `dumpSwapVector` (bytes reversed per element); `abslineinfo` is
  dumped as `int`s so the swap keeps each field. ~48 lines including the `llex.c` warning fence.
* `lunatikc -e big|little` (default host) sets `luaU_dumpswap` when the target differs from the
  host; `-e` with the host order is byte-identical to the default output. A tool built against a
  submodule without the hook fails to link (`luaU_dumpswap`), which is the loud failure wanted.
* Verified: a 32-bit big-endian runner (MIPS32, `qemu-user`, built from the same fork sources with
  `-D_KERNEL -DLUNATIKC`) runs `-e big` chunks compiled on the aarch64 host, full and stripped,
  with correct integer semantics (`7 / 2 == 3`, 64-bit `lua_Integer` constants) and correct error
  line numbers (the swapped `abslineinfo`); the native chunk is rejected there with `int format
  mismatch`, and the `-e big` chunk is rejected by the little-endian kernel the same way.

### Phase 5 — follow-ups (separate plans when picked up)

* **Parser-less kernel build**: `CONFIG_LUNATIK_BYTECODE_ONLY` dropping `lcode/llex/lparser` from
  `Kbuild` with a stub `luaY_parser` (the 5.1 `noparser.c` technique); ~43 KB of text; forces
  `BYTECODE=1` install and text `load` becomes an error. Also a security posture: source can no
  longer be injected through `/dev/lunatik`.
* **Text-only knob**: a module parameter or Kconfig making `lunatik_loadfile` pass `"t"`
  (NetBSD's `kern.lua.bytecode` precedent), for deployments that want the parser as a filter.
* **Fixed-buffer loading**: `'B'` mode for chunks resident in a persistent buffer (firmware
  section, `request_firmware`), saving the copy of code and strings; needs a loader that reads the
  whole chunk once, not `lunatik_loadfile`'s page streaming.
* **Encrypted bytecode**: `luadarken_run` loads with `"t"`; a `"b"` option and `shade.sh` running
  `lunatikc` first.

## Sizing

| Phase | New code | Touches | Risk |
|-------|----------|---------|------|
| 1+3 | 166 lines C, ~50 Makefile | `lunatik_conf.h` (fence only) | low; prototyped, suite green both ways |
| 2 | 1 shell + 5 Lua test files, `check_dmesg` pattern, `runner.lua` trim | `tests/run.sh`, READMEs | low; prototyped |
| 4 | ~48 lines in the `lua/` fork, ~15 in the tool | `lua/` submodule bump | low; prototyped, verified under qemu MIPS BE |
| 5 | per follow-up | `Kbuild`, `Kconfig`, `lunatik_aux.c`, `luadarken.c` | separate plans |

## Non goals

* A Lua-to-bytecode compiler written in Lua, or any reimplementation of the front end: it would
  have to track the `_KERNEL` patch by hand.
* Changing the chunk format, adding a verifier, or signing chunks. Trust is by directory, as for
  source today; a signing story belongs with a kernel lockdown discussion, not here.
* A `.luac` extension, a second `package.path` entry, or any runner/CLI change for phase 1–3.
* Compiling on the device: the point is the host; the device may have no toolchain at all.
* Loader-side byte swapping (OpenWrt 5.1 model): it moves cost into the kernel for every load.

## Risks

* **Header fence regression.** Splitting `lunatik_conf.h` must not change a single macro the
  kernel sees. Check: `make` before/after produces identical `lunatik.ko` text size and the full
  suite passes; diff the preprocessed header under `-D__KERNEL__`.
* **Test harness blind spot.** With `-s`, a failing script prints `?:?:` and `check_dmesg` would
  not notice (`run_script` fails on any output since `e9e57297`). Fixed in the suite commit and
  validated negatively: a failing stripped chunk is reported as `not ok`.
* **Submodule drift.** Phase 4 lands in `luainkernel/lua` first (branch `claude_luac` there);
  a tool built against a submodule without the hook fails to link, so `-e` can never silently
  emit a native chunk.
* **Chunk name leakage.** A chunk keeps the path given at compile time; the install recipe must
  pass `-n` so kernel messages name the installed file, and `-s` installs carry no path at all.
* **`lua_Number` drift.** If the kernel fork ever changes number configuration, the header
  probes catch it (mismatch error), but only at load time; the suite's stock-format rejection
  test is the canary.

## Definition of done, per phase

1. `make` builds `lunatikc`; a chunk it produces, installed as `.lua`, runs under `lunatik run`
   and via `require`; `-s` and `-n` behave as documented; a stock chunk is rejected; kernel build
   unchanged. **Met on the prototype.**
2. `sudo lunatik test luac` green; a deliberately failing stripped chunk is reported as a failure
   by the harness. **Met on the prototype** (8/8; negative validation by hand).
3. `BYTECODE=1 make install` followed by the full suite, green; `file /lib/modules/lua/*.lua` shows
   Lua bytecode under the usual names. **Met on the prototype** (117/117).
4. A big-endian chunk verified on a BE runtime (qemu or hardware), and the native path unchanged.
5. Each follow-up has its own design note before code.

