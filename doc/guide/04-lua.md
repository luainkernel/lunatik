# Lua in the kernel

Lunatik 4.4 is based on
[Lua 5.5 adapted](https://github.com/luainkernel/lua)
to run in the kernel.

## Floating-point numbers

Lunatik **does not** support floating-point arithmetic,
thus it **does not** support `__div` nor `__pow`
[metamethods](https://www.lua.org/manual/5.5/manual.html#2.4)
and the type _number_ has only the subtype _integer_.

## Lua API

Lunatik **does not** support the [os](https://www.lua.org/manual/5.5/manual.html#6.9) library,
floating-point arithmetic (`__div`, `__pow`), or `debug.debug`.
The `math` library is present but all floating-point functions are absent —
only integer operations are supported.

The [io](https://www.lua.org/manual/5.5/manual.html#6.8) library is supported with the
following limitations: there are no default streams (`io.stdin`, `io.stdout`, `io.stderr`),
no default input/output (`io.read`, `io.write`, `io.input`, `io.output`), no process pipes
(`io.popen`), no temporary files (`io.tmpfile`), and no buffering control (`file:setvbuf`).
The available functions are `io.open`, `io.lines`, `io.type`, and the file handle methods
`read`, `write`, `lines`, `flush`, `seek`, and `close`.
On failure, error messages always read `"I/O error"` regardless of the underlying errno.

Lunatik **modifies** the following identifiers:
* [\_VERSION](https://www.lua.org/manual/5.5/manual.html#pdf-_VERSION): is defined as `"Lua 5.5-kernel"`.
* [collectgarbage("count")](https://www.lua.org/manual/5.5/manual.html#pdf-collectgarbage): returns the total memory in use by Lua in **bytes**, instead of _Kbytes_.
* [package.path](https://www.lua.org/manual/5.5/manual.html#pdf-package.path): is defined as `"/lib/modules/lua/?.lua;/lib/modules/lua/?/init.lua"`.
* [require](https://www.lua.org/manual/5.5/manual.html#pdf-require): only supports built-in or already linked C modules, that is, Lunatik **cannot** load kernel modules dynamically.
  In a softirq or hardirq runtime, a hook requires only what the script body loaded: once the runtime is armed, a `require` that would search `package.path`, and [package.searchpath](https://www.lua.org/manual/5.5/manual.html#pdf-package.searchpath), raise `not allowed after module load`, since opening a file sleeps.


