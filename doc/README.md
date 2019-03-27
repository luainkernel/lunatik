Lunatik
========

A port of the Lua interpreter to the Linux kernel.

## Changes to Lua

Lunatik introduces minimal changes to Lua; all changes are related to in-kernel limitations or adjustments.

---

The following standard libraries are **not** present:

* `io`

---

The following standard functions are **not** present:

* `dofile`
* `loadfile`
* `debug.debug`
* `math.abs`
* `math.acos`
* `math.asin`
* `math.atan`
* `math.ceil`
* `math.cos`
* `math.deg`
* `math.exp`
* `math.floor`
* `math.fmod`
* `math.huge`
* `math.modf`
* `math.pi`
* `math.rad`
* `math.sin`
* `math.sqrt`
* `math.tan`
* `math.tointeger`
* `math.type`
* `math.ult`
* `os.clock`
* `os.date`
* `os.difftime`
* `os.exit`
* `os.getenv`
* `os.remove`
* `os.rename`
* `os.setlocale`
* `os.tmpname`
* `package.cpath`
* `package.path`
* `package.searchpath`

---

The following C API functions are **not** present:

* `luaL_dofile`
* `luaL_execresult`
* `luaL_fileresult`
* `luaL_loadfile`
* `luaL_loadfilex`
* `luaopen_io`

---

The following adjustments were made:

* No support for floating point representation. All numbers are integers.

---

The following changes to available functions were made:

#### `collectgarbage([opt [, arg]])`

* **"count"**: returns the total memory in use by Lua in bytes, instead of Kbytes.

All other options are still the same as Lua.

#### `require(modname)`

`require` behaves the same as in Lua, except that it was removed the Lua file loader.

On Linux, the in-kernel C loader queries the kallsyms table for symbols of kernel modules that were previously loaded.
It's the user responsability to load the necessary kernel modules.
The `require` function only works in a kernel compiled with `CONFIG_KALLSYMS`, otherwise it fails.

#### `os.time()`

`os.time()` now takes no arguments and returns the current time in seconds and milliseconds since the UNIX epoch.
