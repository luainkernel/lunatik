---
paths:
  - "**/lib/**"
  - "**/lunatik*.c"
  - "**/lunatik*.h"
  - "**/autogen/**"
---

# The API a script sees

The public API freezes at each major release: a minor only adds. These are the rules the v5.0 freeze
settled (#1292); a binding or a Lua module follows them whichever language it is written in.

They serve a smaller API and a smaller core, never a larger one. A reading of one of them that
multiplies names or threads a mechanism through the core is read again for what the rule is for, and
the smallest shape that keeps that purpose is the one taken: #1537 split `linux.tracing` into three
functions to avoid a boolean that is the very value the call writes, and the RTNL a netdevice callback
runs under grew a flag on the runtime, an error and a check in the core and refusals in `socket`,
`netlink`, `thread` and a runtime's `stop`, before the maintainer asked for a softirq runtime, where
nothing waits on RTNL, and removed them for `lunatik_checkarmed`, which refuses under RTNL too.

* A module whose object is its own type constructs it with `.new`; a module of several types names a
  factory for each (`crypto.shash`, `bpf.hash`, `rcu.table`); a kernel registration takes the verb it
  mirrors (`netfilter.register`, `hid.register`, `fsnotify.watch`, `thread.run`); a hook a kfunc
  dispatches is `attach` and `detach` on the module.
* A registration stops with `stop`, a resource closes with `close`; both are idempotent, and a handle
  that has one offers `__close` equal to it. Dropping a handle stops nothing: a registration stays
  anchored in its runtime until `stop` or the end of the runtime, and the constructor's doc says so.
* A hook callback's decision is its return value. Nil, no value and a raise give the hook's safe
  default, which the registration's doc names; a value the kernel cannot take from a script is refused
  and logged, not passed on. A callback fails an operation the kernel asked for by returning a negative
  errno.
* An expected outcome is a value: nil for "there is none", with the errno's name as a second value when
  the kernel gave one, and false for "did not fit" or "did not happen". A kernel failure, a wrong use
  and an interruption by a stop raise, a kernel failure as the errno's name through `lunatik_throw`.
* A class's name, the `__name` a type error quotes, is the module then the type, joined by a dot
  (`rcu.table`, `crypto.aead`, `lunatik.runtime`): what a script types to reach it.
* Required arguments come first and optional ones last; a set of named fields is a table; a choice the
  binding defines is a string read by `luaL_checkoption`; a kernel value is an integer a `linux.*` table
  names; no positional boolean changes what a call does or how many values it returns. A boolean
  that is the value an accessor writes selects no mode: `linux.tracing([on])` reads given none or
  nil, writes given a boolean, refuses anything else, and is one function.
* A duration a script hands a wait is in milliseconds, a clock or an accounting read is in
  nanoseconds, and every `@tparam` and `@treturn` of a time names its unit.
* A `linux.*` table holds only names a kernel header defines, keyed by the name without its prefix,
  one table per kernel family; a hook's verdict table is `action`. `linux.errno` keeps the `E`, the
  name `linux.errname` gives, and its spec says so with `strip = false`. A constant with no kernel name
  behind it, one the binding defines itself, is built at the binding's opener beside the C that reads
  it, under the module's own name, as `fsnotify.action` is.
* A top-level name belongs to a binding or to Lunatik (`lunatik`, `linux`, `examples`, `tests`), and
  the guide lists them; a script of a product lives in a directory of its own.
* A major release keeps no path for what it replaces: a word, a name or a shim the replacement made
  redundant goes in the release that replaces it, and a compatibility the tree keeps is one the
  maintainer asked for. #1484 first read `run`'s 4.4 words through every 5.x release, from a
  recommendation approved with the rest of a review, until the maintainer asked where that came from.

