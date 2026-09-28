# Lua in the kernel

Lunatik 5.0 is based on
[Lua 5.5 adapted](https://github.com/luainkernel/lua)
to run in the kernel.

## Floating-point numbers

Lunatik **does not** support floating-point arithmetic,
thus it **does not** support `__div` nor `__pow`
[metamethods](https://www.lua.org/manual/5.5/manual.html#2.4)
and the type _number_ has only the subtype _integer_, a 64-bit integer. The `/` operator is floor
division, the same as `//`, so `7 / 2` is `3`; `^` is not an operator; and a numeral with a decimal
point or an exponent, `1.5` or `1e3`, does not parse. A fraction takes fixed point.

## Lua API

Lunatik **does not** support the [os](https://www.lua.org/manual/5.5/manual.html#6.9) library,
floating-point arithmetic (`__div`, `__pow`), or `debug.debug`.
The `math` library keeps `abs`, `max`, `min`, `tointeger`, `ult`, `maxinteger` and `mininteger`.
The rest is absent, `math.random` (use `linux.random`), `math.floor` and `math.type` (use
`type(x) == "number"`) among them. `string.format` has no `%a`, `%e`, `%f` or `%g` conversion,
`string.pack` and `string.unpack` have no `f` or `d` option, and their `n` is a 64-bit integer.

The [io](https://www.lua.org/manual/5.5/manual.html#6.8) library is supported with the
following limitations: there are no default streams (`io.stdin`, `io.stdout`, `io.stderr`),
no default input/output (`io.read`, `io.write`, `io.input`, `io.output`), no process pipes
(`io.popen`), no temporary files (`io.tmpfile`), and no buffering control (`file:setvbuf`).
The available functions are `io.open`, `io.lines`, `io.type`, and the file handle methods
`read`, `write`, `lines`, `flush`, `seek`, and `close`.
On failure no errno reaches the script: `io.open` returns `nil`, `"<file>: (no extra info)"` and
`0`, and a function that raises, such as `io.lines`, says `I/O error`.

Lunatik **modifies** the following identifiers:
* [\_VERSION](https://www.lua.org/manual/5.5/manual.html#pdf-_VERSION): is defined as `"Lua 5.5-kernel"`.
* [`collectgarbage("count")`](https://www.lua.org/manual/5.5/manual.html#pdf-collectgarbage): returns the total memory in use by Lua in **bytes**, instead of _Kbytes_.
* [package.path](https://www.lua.org/manual/5.5/manual.html#pdf-package.path): is defined as `"/lib/modules/lua/?.lua;/lib/modules/lua/?/init.lua"`.
* [require](https://www.lua.org/manual/5.5/manual.html#pdf-require): finds a Lua file on `package.path`, or the opener `luaopen_<name>` a loaded Lunatik module exports; it **cannot** load kernel modules. The CLI loads every module the build produced, and `CONFIG_LUNATIK_<NAME> := n` in the Makefile leaves one out; requiring a C module that is not loaded raises an error naming `luaopen_<name> not found in kernel symbol table`.
* [print](https://www.lua.org/manual/5.5/manual.html#pdf-print): writes to the kernel log (`dmesg -w` or `journalctl -k -f`), not to a terminal, and [warn](https://www.lua.org/manual/5.5/manual.html#pdf-warn) writes there too, as `Lua warning: <message>` at `KERN_ERR`. The REPL and `-e` bring back only what a chunk returns.

Lunatik **adds** the global `_LUNATIK_VERSION`, the Lunatik release.

A coroutine's Lua stack holds at most 200 slots (`LUAI_MAXSTACK`), which bounds recursion and the
values `table.unpack` and a vararg carry: past it, recursion raises `stack overflow` and
`table.unpack` raises `too many results to unpack`.

## Softirq and hardirq runtimes

In a runtime created in softirq or hardirq context, `io` is nil, `require("io")` raises
`'io': process-context class in interrupt-context runtime`, and the `lunatik` table holds only
`cpu()` and `_ENV`, so `lunatik.runtime` and `lunatik.percpu` are absent. A Lua library is required
at the top level of the script, since opening a file sleeps: once the runtime is armed, a `require`
of a module the body did not load, and
[package.searchpath](https://www.lua.org/manual/5.5/manual.html#pdf-package.searchpath), raise
`not allowed after module load`, and `loadfile` fails, and `dofile` raises, with
`cannot load file on non-sleepable runtime`.


