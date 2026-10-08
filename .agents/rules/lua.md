---
paths:
  - "**/*.lua"
  - "**/bin/lunatik"
---

# Lua style

* Line length 120.
* Localize stdlib functions at the top of a new module: `local insert = table.insert`.
* `require("x")` with parentheses.
* Use `table.insert`, not `t[#t+1] = v`.
* No nested function definitions; helpers go at module level.
* Code two scripts of one directory repeat goes in a module beside them that both require: the data
  suite's buffer checks live in `tests/data/zeroing.lua`, required as `tests.data.zeroing`.
* Hooks and callbacks are named `local function`s referenced by name, never anonymous functions inline
  in a table field. A closure of one statement stays where it is used, as a sentinel's `__gc` that
  stops its child does: named, it only moves that statement away from the one place it is read.
* Named constants at the top: `local PORT <const> = 5562`. No magic numbers, and no literal a file
  spells twice: the script path `runner.run` and `runner.stop` both name is one local, or a rename
  of the script leaves a dangling runtime behind.
* CAPS `<const>` marks a scalar constant; a table used as a lookup, dispatch, or allow-list is a
  lowercase name by role — `codecs`, `tokens`, `fields` — never caps, even when it is `<const>`.
* Prefer the standard library (`string.match`, `string.gsub`, `table.*`) over hand written loops.
* The kernel Lua state has no `math.type`; use `type(x) == "number"`.
* A call repeated with the same arguments in one flow is resolved once into a local:
  `local kind = type(spec)`, then compare `kind`.
* Dispatch over a type or a key uses a table whose handlers are declared in place —
  `function codecs.string(format)` — not an if/elseif chain. Look the handler up once and guard the
  result with `== nil`; a looked-up constructor is named `new`, never the same name as what it builds.
* `cond and f() or g()` only when `f` is guaranteed to return a truthy value: if `f()` returns nil or
  false, `g()` runs too. Side effects and doubtful returns take if/else.
* Two returns that differ in one value are one return whose value is that choice: `return msg, msg
  and net.ntoa(ip) or ip, port` in `inet.udp:receivefrom`, where an `if` returned `nil, ip` above a
  second `return`, the `and`/`or` held to the rule above (`net.ntoa` answers a string). The trailing
  `nil` the shorter arm left off reads the same to every caller but `select("#", ...)`, so a test
  reads the values and not their count. `lua-style.sh` names the `if` that returns `nil` above a
  return of what it tested.
* Name variables by role, not by structure: `proxy`, not `tbl`; `openproxy` to pair with `openqueue`,
  not `opentable`.
* A module that makes objects returns a class or namespace table named for the module, never `M` and
  never a bare function; that return is for builders like `class` and `struct`. The object holds its
  underlying handle in a named field — `socket`, `tfm` — not one prefixed with an underscore, and is
  constructed through `.new` or a `:__call` method on the class, as `hkdf` and `inet` do, not a
  metatable wrapped around the module to make it callable, which nothing in the tree does. The
  instance metatable is named for what it is, not `mt`.
* A proxy's metamethods do not allocate per access. `bpf.map`'s `view` resolves a key in one lookup;
  an `__index` that builds a closure on every method fetch, or composes `"get" .. key`, pays that on
  every packet in a softirq path, and the composed name collides with a real method spelled the same.
  A fixed set of fields is a table looked up once, not a name assembled each time.

Inside a CLI dostring, require once at startup and call by name afterwards:

    lunatik.foo = require("lunatik.foo")
    lunatik.foo.method(...)

Never `require("foo").method()`. A kernel script does the same with a local:
`local genl = require("linux.genl")` once, then `genl.id`, `genl.ctrl` and `genl.layout`, never a
`require` per field.

