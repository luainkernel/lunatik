# Testing the bytecode compiler

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on
`dmesg` or on what userspace observes. `tests/io/test.sh` is the closest model (one `.sh`, one
`.lua`, `run_script` + `check_dmesg`); read it and `tests/lib.sh` first.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test luac`.

## What this suite needs that others do not

**A host step.** The kernel script under test is not installed by `make tests_install` as is: the
suite compiles it at run time with the installed `lunatikc` from the installed source
(`/lib/modules/lua/tests/luac/*.lua`) into a sibling `.lua` that is the chunk. That keeps `make
tests_install` unchanged (it copies `.lua` sources) and exercises the real install path of the
tool. `cleanup()` removes the generated chunks.

**A skip gate for the tool.** If `lunatikc` is not on `PATH` (`make install` not run, or a
package without it), `run.sh` reports `ktap_skip` for the whole suite rather than failing.

**A harness fix.** `check_dmesg` in `tests/lib.sh` recognised Lua errors by `\.lua:[0-9]+:`
(`run_script` fails on any output, so it was already covered). A **stripped** chunk reports errors
as `?:?:` (no source, no line), so a failing stripped script passed `check_dmesg`. The pattern now
also matches `\?:\?:`; validated negatively on the prototype (a failing stripped chunk is `not
ok`). Verified messages:

```
full:   /lib/modules/lua/tests/luac/err_bc.lua:8: attempt to index a nil value (local 't')
strip:  ?:?: attempt to index a nil value
```

The suite's own scripts stay source under `make tests_install`, so they are compiled at run
time: `tests/luac/run.sh` writes `hello_bc.lua`, `hello_s.lua`, `lib_bc.lua`, `err_bc.lua`,
`err_s.lua` and the patched `stock.lua` next to the sources and removes them in `cleanup()`.

**A runner fix.** `runner.lua`'s `trim()` mangled any script path containing a word, one
character and `lua` (`tests/luac/hello_bc` → `testsc/hello_bc`); the suite is what found it. Fixed
on the branch; without it the suite cannot be named `luac`.

## Test matrix

Coverage means the matrix of operation × variant × outcome, including the successes and the clean
failures, not a list of features.

### Phase 1–2: compile and run

| Operation | Variant | Expected |
|-----------|---------|----------|
| `lunatikc t.lua` → `lunatik run` | full | script's `dmesg` marker present, no error |
| same | `-s` | marker present, no error |
| same | `-n @/lib/modules/lua/tests/luac/t.lua` + forced error | error message names the installed path and line |
| same | `-s` + forced error | `?:?:` error, and the harness **fails** the test (negative validation of the lib.sh fix) |
| `require("tests.luac.lib")` from a text script | lib installed as chunk | module loads and its function returns |
| `lunatikc` on a file with a syntax error | | non-zero exit, message with `file:line:`, no output file |
| `lunatikc` on a binary input | | non-zero exit (`attempt to load a binary chunk`), no output |
| stock-format chunk installed as `.lua` | crafted header (`LUAC_NUM` as a double) | `bad binary format (Lua number format mismatch)` |
| `load(chunk, "=x", "t")` in the kernel | chunk read with `io` | `attempt to load a binary chunk (mode is 't')` |
| integer semantics | `7 / 2`, `2^3` absent, `3.5` literal | `3`; `^` is a syntax error on the host; `3.5` is `malformed number` on the host |

### Phase 3: bytecode install

| Operation | Expected |
|-----------|----------|
| `BYTECODE=1 make install` then `sudo lunatik test` | every suite green (driver, runner, net, mailbox, socket, netlink, bpf libs all run as stripped chunks) — 117/117 on the prototype |
| `file /lib/modules/lua/net.lua` | "Lua bytecode" |
| `lunatik run examples/…` | examples run as chunks |

### Phase 4: cross-endian

The suite covers what a single-endian box can: host-order output is byte-identical (`cmp`) and
foreign-order output is rejected by the kernel header probes. The positive cross run needs a
big-endian runtime; it was done by hand and is reproducible with the distribution cross tools:

```sh
sudo apt install gcc-mips-linux-gnu qemu-user-static
mips-linux-gnu-gcc -static -std=gnu99 -O1 -w -D_KERNEL -DLUNATIKC -DLUA_USE_LINUX \
        -I. -Ilua -o be_run <a loadbufferx "b" + pcall driver> lua/{core}.c -lm
bin/lunatikc -e big -o chunk.luac script.lua
qemu-mips-static ./be_run chunk.luac
```

| Operation | Verified |
|-----------|----------|
| `-e big` chunk (full and stripped) on MIPS32 BE under qemu | runs; `7 / 2 == 3`, 64-bit integer constants intact, error lines correct |
| native LE chunk on the BE runtime | `int format mismatch` |
| `-e big` chunk on the LE kernel | `int format mismatch` (suite) |
| `-e <host order>` | byte-identical to the default output (suite, `cmp`) |
| tool built against a `lua/` without the hook | link error on `luaU_dumpswap` |

## How to fake a stock chunk without a stock `luac`

The suite cannot depend on `luac5.5` being installed. Take a good chunk and patch the
`lua_Number` probe: the header is `\x1bLua\x55\x00` + `LUAC_DATA` (6 bytes) + four
`size,value` blocks; the last block is `\x08` + 8 bytes. Replace those 8 bytes with the IEEE-754
little-endian image of `-370.5` (`00 00 00 00 00 28 77 c0`) with `printf | dd conv=notrunc`.
The kernel must answer `Lua number format mismatch` — the same message a real stock chunk gives
(verified with an upstream 5.5.0 `luac`).

