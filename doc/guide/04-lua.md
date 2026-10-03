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
A file `loadfile`, `dofile` or `require` opens and cannot read fails with the errno's name:
`EINVAL` for a directory. A file `loadfile` or `dofile` cannot open fails with `cannot open <file>: `
and the errno's name, `ENOENT` for a missing one.

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

A call that crosses C, through `pcall`, a metamethod, a callback a binding makes, a coroutine
resumed inside another or a runtime a script creates or resumes, nests on the kernel stack instead,
which Lunatik bounds in bytes (`LUAI_MAXCCALLS`): past five eighths of it (`THREAD_SIZE`), counted
from where the kernel entered Lua, at a hook, a thread's start, the CLI's write or the close that
runs a runtime's finalizers, such a call raises `C stack overflow`, as a chunk whose syntax nests
that deep does. A runtime a script creates or resumes counts from where its creator or resumer was
entered, so a script that creates itself runs out too. Under `xpcall`, a message handler called past
the bound raises in turn, and the call ends with `error in error handling`. On the task stack the
call also raises once a quarter of the stack is all that is left, so a hook entered deep, as a
kprobe in the network stack is, or a runtime another script closes, gets what remains; a hook on an
interrupt stack is bounded from its entry alone.

A string pattern nests at most 32 levels deep: the match takes one, each capture two, and each
position capture `()` and each item with `?`, `*`, `+` or `-` that matches one more. Past it,
`string.find`, `string.match`, `string.gmatch` and `string.gsub` raise `pattern too complex`.

## Softirq and hardirq runtimes

In a runtime created in softirq or hardirq context, `io` is nil, `require("io")` raises
`'io': process-context class in interrupt-context runtime`, and the `lunatik` table holds only
`cpu()` and `_ENV`, so `lunatik.runtime` and `lunatik.percpu` are absent. A Lua library is required
at the top level of the script, since opening a file sleeps: once the runtime is armed, a `require`
of a module the body did not load,
[package.searchpath](https://www.lua.org/manual/5.5/manual.html#pdf-package.searchpath) and `dofile`
raise `not allowed once the runtime is armed`, and `loadfile` returns it as its error.


