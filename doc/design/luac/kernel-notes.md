# Kernel notes: bytecode for the kernel Lua

Reference sheet for `lunatikc`. Verified on 2026-08-23 against the `lua/` submodule at `d7ca49b3`
(upstream Lua 5.5.0 plus the `_KERNEL` patch), `lunatik_conf.h`, and a running 6.8.0-136 aarch64
kernel with the prototype on the `claude_luac` branch. Re-check whenever `lua/` is bumped.

## The one fact that shapes everything

The kernel Lua is **not** stock Lua 5.5, and the difference is visible in the bytecode. Under
`_KERNEL` (the define every kernel object is built with, `Kbuild` `LUNATIK_FLAGS`):

| Where | What changes | Effect on a chunk |
|-------|--------------|-------------------|
| `lua/lopcodes.h` | `OP_LOADF`, `OP_POWK`, `OP_DIVK`, `OP_POW`, `OP_DIV` are compiled out | every opcode after `OP_LOADI` has a different number than upstream |
| `lua/lparser.c` | `/` maps to `OPR_IDIV`; `^` is not an operator; no `TK_FLT` | `7 / 2` compiles to `OP_IDIV` (= 3) |
| `lua/ldump.c`, `lua/lundump.c` | `LUA_VNUMFLT` and `dumpNumber`/`loadNumber` compiled out | no float constants exist |
| `lunatik_conf.h` | `LUA_NUMBER` is `LUA_INTEGER` | header probe `LUAC_NUM = cast_num(-370.5)` is the 8-byte integer `-370` |

A chunk from the distribution `luac` (or from `string.dump` in any userspace Lua) therefore fails
the header (`bad binary format (Lua number format mismatch)`, verified), and even a hand-patched
header would run the wrong opcodes. The compiler has to be built from `lua/` with `-D_KERNEL` and the
same `lunatik_conf.h` number configuration. There is no shortcut through a reimplementation.

## Chunk format (Lua 5.5, `lua/ldump.c` / `lua/lundump.c`)

Header, `dumpHeader` / `checkHeader` (`lundump.c:381`):

| Field | Value | Endian-dependent |
|-------|-------|------------------|
| `LUA_SIGNATURE` | `"\x1bLua"` | no |
| `LUAC_VERSION` | `0x55` (5.5) | no |
| `LUAC_FORMAT` | `0` | no |
| `LUAC_DATA` | `"\x19\x93\r\n\x1a\n"` | no |
| `sizeof(int)` + `int LUAC_INT` | `4`, `-0x5678` | **yes** (raw bytes) |
| `sizeof(Instruction)` + `LUAC_INST` | `4`, `0x12345678` | **yes** |
| `sizeof(lua_Integer)` + `LUAC_INT` | `8`, `-0x5678` | **yes** |
| `sizeof(lua_Number)` + `LUAC_NUM` | `8`, `-370` (integer, see above) | **yes** |

Body. Lua 5.5 encodes every count, size and `int` field as a 7-bit-per-byte varint (`dumpVarint`,
`dumpSize`, `dumpInt`), and **integer constants as zigzag varints** (`dumpInteger`, `ldump.c:127`:
in 5.4 they were raw `loadVar`) — all endian-independent. Strings are dumped once and reused by
index. What is dumped raw, in host byte order:

* the instruction vector (`dumpCode`: `dumpAlign` then `dumpVector(f->code)`),
* `abslineinfo` (array of `{int pc; int line}`, `dumpAlign` + `dumpVector`; absent with `-s`),
* the four header probes above.

`lineinfo` is a byte vector (portable). Upvalue descriptors, local names, `linedefined`, `numparams`
and flags are bytes or varints (portable). `lundump.c:52` states the intended hook: "All high-level
loads go through loadVector; you can change it to adapt to the endianness of the input".

**Consequence for cross-compilation.** `lua_Integer` is `long long` on every Lunatik target (the
kernel build never defines `LUA_32BITS`; `Kbuild` only adds libgcc 64-bit division helpers on
`!CONFIG_64BIT`), `int` and `Instruction` are 4 bytes everywhere. So a 64-bit little-endian host
produces chunks that load unchanged on 32-bit little-endian targets (ARM, x86). Only a big-endian
target (e.g. MIPS routers on OpenWrt) needs a byte-swapping dump, and only for three things: the
32-bit instruction vector, `abslineinfo` (gone with `-s`) and the header probes. That hook does
not exist upstream; it lives in the `lua/` fork (`ldump.c`, branch `claude_luac`) behind the
`LUNATIKC` define that only the tool build sets — swap on the dump side, the eLua `luac.cross`
model, not the OpenWrt 5.1 model of swapping on load, which would cost the kernel.

## Stripping (`lua_dump(..., strip)`)

`-s` drops `source`, `lineinfo`, `abslineinfo`, local variable names and upvalue names
(`dumpDebug`). Verified effect on a runtime error:

```
full:   ...err.lua:3: attempt to index a nil value (local 't')
strip:  ?:?: attempt to index a nil value
```

The chunk name is baked in at compile time as `"@<path given to the compiler>"`; the tool must let
the caller set it (otherwise kernel error messages point at a build-tree path).

## How the kernel loads a file today

* `lunatik_core.c:219` builds the path as `LUA_ROOT "<script>.lua"` (`/lib/modules/lua/`), so the
  script name is relative and the `.lua` suffix is fixed — a bytecode file installed **as `.lua`**
  is picked up with no change; `lua_load` detects a binary chunk by `LUA_SIGNATURE[0]`.
* `lunatik_core.c:239` calls `lunatik_loadfile(L, script, NULL)`: mode `NULL` means `"bt"`.
  `lunatik_conf.h` redefines `luaL_loadfilex` to `lunatik_loadfile`, so `require`'s `searcher_Lua`
  (`lua/loadlib.c`) takes the same path with the same mode. **Binary chunks are accepted everywhere
  already.**
* `lunatik_loadfile` (`lunatik_aux.c:36`) reads through a `PAGE_SIZE` `kmalloc` buffer with
  `kernel_read`; it never skips a `#!` line or BOM (unlike upstream `luaL_loadfilex`).
* `package.path` is `LUA_ROOT "?.lua;" LUA_ROOT "?/init.lua"` (`lunatik_conf.h`): a `.luac` suffix
  would need an entry there. Not needed if bytecode is installed under the `.lua` name.
* `lib/luadarken.c:120` loads the decrypted buffer with mode `"t"` — the one explicit text-only
  load in the tree. Encrypted bytecode is a follow-up, not a conflict.
* `/dev/lunatik` writes go through `driver.lua`'s `load(buf)` (mode `"bt"`), so the CLI could also
  send a chunk — but the CLI sends `lunatik.runner.run("<name>")` strings, not script bodies.

## Lua 5.5 "fixed buffer" mode

`lua_load` mode `'B'` (`ldo.c:1130`, `luaU_undump(..., fixed=1)`) keeps the instruction vector,
line tables and strings pointing **into the caller's buffer** (`PF_FIXED`, `getaddr` in
`lundump.c`) instead of copying them; `dumpAlign` pads the dump so those vectors are aligned in
place. `lbaselib.c:348` forbids `'B'` from Lua code. The buffer must outlive the closure. This is
the zero-copy path for bytecode living in a persistent kernel buffer (firmware section, a
`vmalloc`ed image loaded once); `lunatik_loadfile`'s page-sized streaming buffer does not qualify.
Opportunity, not a requirement (see non goals in `plan.md`).

## Bytecode trust

Lua has had no bytecode verifier since 5.2 (removed after Peter Cawley's exploits of the 5.1
verifier; the 5.5 manual: "Lua does not check the consistency of binary chunks. Maliciously crafted
binary chunks can crash the interpreter"). `lundump.c` checks the header and sizes, not the
semantics of instructions; `luai_verifycode` is an empty hook. A hostile chunk can read and write
arbitrary memory of the Lua state — in the kernel, that is a kernel compromise. The kernel already
runs Lua **source** with full kernel privileges from a root-owned directory over a root-only
device, so accepting bytecode from the same directory does not widen who can run code; it only
removes the parser as a sanity filter. Precedent: NetBSD's kernel Lua loads through `"bt"` but
refuses the `0x1b` signature unless `kern.lua.bytecode=1` (default 0). The consequence for design:
never add a path that loads bytecode from an untrusted source, and keep a text-only knob available
for deployments that want the parser as a filter (mode `"t"` in `lunatik_loadfile`, see `plan.md`
risks).

## Other precedents worth knowing

* **eLua `luac.cross`** (5.1): `-cci bits -ccn type bits -cce big|little`; a `DumpTargetInfo`
  struct and byte swapping on the dump side, a separate `luaU_dump_crosscompile` entry point. The
  closest model for a cross-endian Lunatik dump.
* **NodeMCU `luac.cross`** (5.3): host built with the target's number config, no swapping (host and
  ESP both little-endian); its LFS (bytecode executed from flash) is the ancestor of 5.5's fixed
  buffers.
* **OpenWrt** (5.1 package): swap on *load* (`030-archindependent-bytecode.patch`), host `luac`
  for MIPS BE routers. Loader-side swapping is the option we do not want (it costs the kernel).
* **Lua 5.1 `etc/noparser.c`**: stub `luaY_parser` + drop `lcode/llex/lparser` ("35 % of the
  core"). 5.5's `f_parser` (`ldo.c:1123`) still only calls `luaU_undump` or `luaY_parser`, so the
  technique applies unchanged to a bytecode-only kernel build.
* **FreeBSD lualoader**: same integer-only `lua_Number` trick (`LUA_FLOAT_INT64`), ships source.
* No pure-Lua compiler targets 5.4/5.5; the 5.5 format (string reuse, alignment) has readers but
  no independent writer. The interpreter's own `ldump.c` is the only correct writer.

## Sizes (for the "no parser in the kernel" follow-up)

`size` on a 6.8 aarch64 build: `lparser.o` 19556 + `lcode.o` 14944 + `llex.o` 8873 = ~43 KB of
text out of 234 KB in `lunatik.ko` (~18 %). `ldump.o` is 3 KB and `lundump.o` 4.5 KB. Dropping the
front end is a real but modest saving; it also removes `load`/`loadstring` of text, `string.dump`
stays. Not part of the first phases.

## Host build of the compiler (verified)

`lua/` has no `luac.c` (only upstream `lua.c`); `onelua.c` still references it under `MAKE_LUAC`.
A host compiler needs only the core: `lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem
lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio lauxlib` — **not** `lbaselib`,
`loadlib`, `linit`, `liolib`, which under `_KERNEL` reference `luaL_loadfilex`/`lsys_*` provided by
`lunatik_conf.h`. Built with `-D_KERNEL -DLUA_USE_LINUX` and a `lunatik_conf.h` whose kernel-only
parts (`printk`, `<linux/module.h>`, `<linux/random.h>`, `lunatik_loadfile`, `LUA_EXTRASPACE`
struct) are fenced with `#ifdef __KERNEL__`, the result is a ~200 KB static binary whose output the
kernel runs (verified: full and stripped chunks, `7/2 == 3`).

Details that bit during the prototype:

* `lua_dump`'s writer is called with `size == 0` blocks; `fwrite(p, 0, 1, f)` returns 0 and looks
  like a failure. Treat `size == 0` as success.
* `luaL_loadbufferx(..., "t")` on the host so that the tool never re-dumps a chunk it did not
  compile (a stock chunk fed by mistake is rejected at the parse step, not silently copied).
* The `lunatik_conf.h` redefinition of `lua_getlocaledecpoint` must stay under `__KERNEL__` (the
  host `luaconf.h` already defines it; redefining warns).

