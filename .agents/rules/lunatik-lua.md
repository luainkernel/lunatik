---
paths:
  - "**/*.lua"
  - "**/bin/lunatik"
---

# Lua of Lunatik

`harness/.agents/rules/lua.md` holds for `bin/lunatik` too; this file adds what Lunatik's Lua asks
beside it.

* The kernel Lua state has no `math.type`; use `type(x) == "number"`.

Inside a CLI dostring, require once at startup and call by name afterwards, never
`require("foo").method()`:

    lunatik.foo = require("lunatik.foo")
    lunatik.foo.method(...)

