# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](lunatik.lua) (written in Lua =)) and a [command line tool](sbin/lunatik)
to load and run scripts and manage runtime environments from the user space;
a [C API](#lunatik-c-api) to load and run scripts and manage runtime environments from the kernel;
and [Lua APIs](#lunatik-lua-apis) for binding kernel facilities to Lua scripts. 
Lunatik also offers a [shell script](sbin/lunatik.sh) as a helper for managing its kernel modules.

Here is an example of a character device driver written in Lua using Lunatik
to generate random ASCII printable characters:
```Lua
-- /lib/modules/lua/passwd.lua
--
-- implements /dev/passwd for generate passwords
-- usage: $ sudo sbin/lunatik --run passwd
--        $ head -c <width> /dev/passwd

local device = require("device")
local linux  = require("linux")

local function nop() end -- do nothing

local s = linux.stat
local driver = {name = "passwd", open = nop, release = nop, mode = s.IRUGO}

function driver:read() -- read(2) callback
	-- generate random ASCII printable characters
	return string.char(linux.random(32, 126))
end

-- creates a new character device
device.new(driver)
```

## Usage

```
make
sudo sbin/lunatik.sh install # copy lunatik.lua to /lib/modules/lua
sudo sbin/lunatik.sh start   # load Lunatik kernel modules
sudo sbin/lunatik.sh run     # execute sbin/lunatik REPL
Lunatik 3.0  Copyright (C) 2023 ring-0 Ltda.
> return 42 -- execute this line in the kernel
42
```

### sbin/lunatik

```Shell
usage: sbin/lunatik [[--run] <script>] [--stop <script>]
```

* `--run`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`
* `--stop`: stop the runtime environment created to run the script `<script>`
* `default`: start a _REPL (Read–Eval–Print Loop)_

### sbin/lunatik.sh

```
usage: sbin/lunatik.sh {start|stop|restart|status|install|run}
```

* `start`: load Lunatik kernel modules
* `stop`: remove Lunatik kernel modules
* `restart`: reload Lunatik kernel modules
* `status`: show what Lunatik kernel modules are currently loaded
* `install`: copy `lunatik.lua` device driver to `/lib/modules/lua`
* `run`: execute `sbin/lunatik` REPL

## Lua Version

Lunatik 3.0 is based on
[Lua 5.4 adapted](https://github.com/luainkernel/lua)
to run in the kernel.

### Floating-point numbers

Lunatik **does not** support floating-point arithmetic,
thus it **does not** support `__div` nor `__pow`
[metamethods](https://www.lua.org/manual/5.4/manual.html#2.4)
and the type _number_ has only the subtype _integer_.

### Lua API

Lunatik **does not** support both [io](https://www.lua.org/manual/5.4/manual.html#6.8) and
[os](https://www.lua.org/manual/5.4/manual.html#6.9) libraries,
and the given identifiers from the following libraries:
* [debug.debug](https://www.lua.org/manual/5.4/manual.html#pdf-debug.debug),
[math.acos](https://www.lua.org/manual/5.4/manual.html#pdf-math.acos),
[math.asin](https://www.lua.org/manual/5.4/manual.html#pdf-math.asin),
[math.atan](https://www.lua.org/manual/5.4/manual.html#pdf-math.atan),
[math.ceil](https://www.lua.org/manual/5.4/manual.html#pdf-math.ceil),
[math.cos](https://www.lua.org/manual/5.4/manual.html#pdf-math.cos),
[math.deg](https://www.lua.org/manual/5.4/manual.html#pdf-math.deg),
[math.exp](https://www.lua.org/manual/5.4/manual.html#pdf-math.exp),
[math.floor](https://www.lua.org/manual/5.4/manual.html#pdf-math.floor),
[math.fmod](https://www.lua.org/manual/5.4/manual.html#pdf-math.fmod),
[math.huge](https://www.lua.org/manual/5.4/manual.html#pdf-math.huge).
[math.log](https://www.lua.org/manual/5.4/manual.html#pdf-math.log),
[math.modf](https://www.lua.org/manual/5.4/manual.html#pdf-math.modf),
[math.pi](https://www.lua.org/manual/5.4/manual.html#pdf-math.pi),
[math.rad](https://www.lua.org/manual/5.4/manual.html#pdf-math.rad),
[math.random](https://www.lua.org/manual/5.4/manual.html#pdf-math.random),
[math.randomseed](https://www.lua.org/manual/5.4/manual.html#pdf-math.randomseed),
[math.sin](https://www.lua.org/manual/5.4/manual.html#pdf-math.sin),
[math.sqrt](https://www.lua.org/manual/5.4/manual.html#pdf-math.sqrt),
[math.tan](https://www.lua.org/manual/5.4/manual.html#pdf-math.tan),
[math.type](https://www.lua.org/manual/5.4/manual.html#pdf-math.type),
[package.cpath](https://www.lua.org/manual/5.4/manual.html#pdf-package.cpath).

Lunatik **modifies** the following identifiers:
* [\_VERSION](https://www.lua.org/manual/5.4/manual.html#pdf-_VERSION): is defined as `"Lua 5.4-kernel"`.
* [collectgarbage("count")](https://www.lua.org/manual/5.4/manual.html#pdf-collectgarbage): returns the total memory in use by Lua in **bytes**, instead of _Kbytes_.
* [package.path](https://www.lua.org/manual/5.4/manual.html#pdf-package.path): is defined as `"/lib/modules/lua/?.lua;/lib/modules/lua/?/init.lua"`.
* [require](https://www.lua.org/manual/5.4/manual.html#pdf-require): only supports built-in or already linked C modules, that is, Lunatik **cannot** load kernel modules dynamically.

### C API

Lunatik **does not** support
[luaL\_Stream](https://www.lua.org/manual/5.4/manual.html#luaL_Stream),
[luaL\_execresult](https://www.lua.org/manual/5.4/manual.html#luaL_execresult),
[luaL\_fileresult](https://www.lua.org/manual/5.4/manual.html#luaL_fileresult),
[luaopen\_io](https://www.lua.org/manual/5.4/manual.html#pdf-luaopen_io) and
[luaopen\_os](https://www.lua.org/manual/5.4/manual.html#pdf-luaopen_os).

Lunatik **modifies** [luaL\_openlibs](https://www.lua.org/manual/5.4/manual.html#luaL_openlibs) to remove [luaopen\_io](https://www.lua.org/manual/5.4/manual.html#pdf-luaopen_io) and [luaopen\_os](https://www.lua.org/manual/5.4/manual.html#pdf-luaopen_os).

## Lunatik C API

```C
#include <lunatik.h>
```

#### lunatik\_runtime
```C
int lunatik_runtime(lunatik_runtime_t **pruntime, const char *script, bool sleep);
```
_lunatik\_runtime()_ creates a new `runtime` environment then loads and runs the script
`/lib/modules/lua/<script>.lua` as the entry point for this environment.
It _must_ only be called from _process context_.
The `runtime` environment is composed by
a [Lua state](https://www.lua.org/manual/5.4/manual.html#lua_State), 
a [lock type](https://docs.kernel.org/locking/locktypes.html) and
a [reference counter](https://www.kernel.org/doc/Documentation/kref.txt).
If `sleep` is _true_, it will use a [mutex](https://docs.kernel.org/locking/mutex-design.html)
for locking the `runtime` environment and the
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html)
flag for allocating new memory later on on
[lunatik\_run()](https://github.com/luainkernel/lunatik#lunatik_run) calls.
Otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik\_runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api)
and, if `sleep` is _true_, it also opens the
[lunatik](https://github.com/luainkernel/lunatik#lunatik-1)
library to make them available for the `script`.
If successful, _lunatik\_runtime()_ sets the address pointed by `pruntime` and
[Lua's extra space](https://www.lua.org/manual/5.4/manual.html#lua_getextraspace)
with a pointer for the new created `runtime` environment,
sets the _reference counter_ to `1` and then returns `0`. 
Otherwise, it returns `-ENOMEM`, if insufficient memory is available; 
or `-EINVAL`, if it fails to load or run the `script`.

##### Example
```Lua
-- /lib/modules/lua/mydevice.lua
function myread(len, off)
	return "42"
end
```

```C
static lunatik_runtime_t *runtime;

static int __init mydevice_init(void)
{
	return lunatik_runtime(&runtime, "mydevice", true);
}

```

#### lunatik\_stop
```C
int lunatik_stop(lunatik_runtime_t *runtime);
```
_lunatik\_stop()_
[closes](https://www.lua.org/manual/5.4/manual.html#lua_close)
the
[Lua state](https://www.lua.org/manual/5.4/manual.html#lua_State)
created for this `runtime` environment and decrements the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt).
Once the reference counter is decremented to zero, the
[lock type](https://docs.kernel.org/locking/locktypes.html)
and the memory allocated for the `runtime` environment are released.
If the `runtime` environment has been released, it returns `1`;
otherwise, it returns `0`.

#### lunatik\_run
```C
void lunatik_run(lunatik_runtime_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
_lunatik\_run()_ locks the `runtime` environment and calls the `handler`
passing the associated Lua state as the first argument followed by the variadic arguments.
If the Lua state has been closed, `ret` is set with `-ENXIO`;
otherwise, `ret` is set with the result of `handler(L, ...)` call.
Then, it restores the Lua stack and unlocks the `runtime` environment.
It is defined as a macro.

##### Example
```C
static int l_read(lua_State *L, char *buf, size_t len, loff_t *off)
{
	size_t llen;
	const char *lbuf;

	lua_getglobal(L, "myread");
	lua_pushinteger(L, len);
	lua_pushinteger(L, *off);
	if (lua_pcall(L, 2, 2, 0) != LUA_OK) { /* calls myread(len, off) */
		pr_err("%s\n", lua_tostring(L, -1));
		return -ECANCELED;
	}

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(len, llen);
	if (copy_to_user(buf, lbuf, llen) != 0)
		return -EFAULT;

	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static ssize_t mydevice_read(struct file *f, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	lunatik_runtime_t *runtime = (lunatik_runtime_t *)f->private_data;

	lunatik_run(runtime, l_read, ret, buf, len, off);
	return ret;
}
```

#### lunatik\_get
```C
void lunatik_get(lunatik_runtime_t *runtime);
```
_lunatik\_get()_ increments the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `runtime` environment.

#### lunatik\_put
```C
int lunatik_put(lunatik_runtime_t *runtime);
```
_lunatik\_put()_ decrements the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `runtime` environment.
If the `runtime` environment has been released, it returns `1`;
otherwise, it returns `0`.

#### lunatik\_toruntime
```C
lunatik_runtime_t *lunatik_toruntime(lua_State *L);
```
_lunatik\_toruntime()_ returns the `runtime` environment referenced by the `L`'s
[extra space](https://www.lua.org/manual/5.4/manual.html#lua_getextraspace).

## Lunatik Lua APIs

### lunatik

The `lunatik` library provides support to load and run scripts and manage runtime environments from Lua. 

#### `lunatik.runtime(script [, sleep])`

_lunatik.runtime()_ creates a new
[runtime environment](https://github.com/luainkernel/lunatik#lunatik_runtime)
then loads and runs the script
`/lib/modules/lua/<script>.lua` as the entry point for this environment.
It returns a
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
representing the `runtime` environment.
If `sleep` is _true_ or omitted, it will use a [mutex](https://docs.kernel.org/locking/mutex-design.html)
and
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html);
otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik.runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api),
but differently from
[lunatik\_runtime()](https://github.com/luainkernel/lunatik#lunatik_runtime),
it **does not** open the `lunatik` library.

#### `lunatik.stop(runtime)`, `runtime:stop()`

_lunatik.stop()_
[stops](https://github.com/luainkernel/lunatik#lunatik_stop)
the `runtime` environment and clear its reference from the runtime
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1).

### device

The `device` library provides support for writting
[character device drivers](https://static.lwn.net/images/pdf/LDD3/ch03.pdf)
in Lua.

#### `device.new(driver)`

_device.new()_ returns a new `device`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
and installs its `driver` in the system.
The `driver` **must** be defined as a table containing the following field:
* `name`: string defining the device name; it is used for creating the device file (e.g., `/dev/<name>`).

The `driver` table might optionally contain the following fields:
* `read`: callback function to handle the
[read operation](https://docs.kernel.org/filesystems/vfs.html#id2)
on the device file.
It receives the `driver` table as the first argument
followed by two integers,
the `length` to be read and the file `offset`.
It should return a string and, optionally, the `updated offset`.
If the length of the returned string is greater than the requested `length`,
the string will be corrected to that `length`. 
If the `updated offset` is not returned, the `offset` will be updated with `offset + length`.
* `write`: callback function to handle the
[write operation](https://docs.kernel.org/filesystems/vfs.html#id2)
on the device file.
It receives the `driver` table as the first argument
followed by the string to be written and
an integer as the file `offset`.
It might return optionally the written `length` followed by the `updated offset`.
If the returned length is greater than the requested `length`,
the returned length will be corrected.
If the `updated offset` is not returned, the `offset` will be updated with `offset + length`.
* `open`: callback function to handle the
[open operation](https://docs.kernel.org/filesystems/vfs.html#id2)
on the device file.
It receives the `driver` table and it is expected to return nothing.
* `release`: callback function to handle the
[release operation](https://docs.kernel.org/filesystems/vfs.html#id2)
on the device file.
It receives the `driver` table and it is expected to return nothing.
* `mode`: an integer specifying the device
[file mode](https://github.com/luainkernel/lunatik#linuxstat).

If an operation callback is not defined, the `device` returns `-ENXIO` to VFS on its access.

#### `device.delete(dev)`, `dev:delete()`

_device.delete()_ removes a device `driver` specified by the `dev`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
from the system.

### linux

The `linux` library provides support for some Linux kernel facilities.

#### `linux.random([m [, n]])`

_linux.random()_ mimics the behavior of
[math.random](https://www.lua.org/manual/5.4/manual.html#pdf-math.random),
but binding _<linux/random.h>_'s
[get\_random\_u32()](https://elixir.bootlin.com/linux/latest/source/include/linux/random.h#L42)
and
[get\_random\_u64()](https://elixir.bootlin.com/linux/latest/source/include/linux/random.h#L43)
APIs.

When called without arguments,
produces an integer with all bits (pseudo)random.
When called with two integers `m` and `n`,
_linux.random()_ returns a pseudo-random integer with uniform distribution in the range `[m, n]`.
The call `math.random(n)`, for a positive `n`, is equivalent to `math.random(1, n)`.

#### `linux.stat`

_linux.stat_ is a table that exports
[\<linux/stat.h\>](https://elixir.bootlin.com/linux/latest/source/include/linux/stat.h)
integer flags to Lua.

* `"IRWXUGO"`: permission to _read_, _write_ and _execute_ for _user_, _group_ and _other_.
* `"IRUGO"`: permission only to _read_ for _user_, _group_ and _other_.
* `"IWUGO"`: permission only to _write_ for _user_, _group_ and _other_.
* `"IXUGO"`: permission only to _execute_ for _user_, _group_ and _other_.

### notifier

The `notifier` library provides support for the kernel
[notifier chains](https://elixir.bootlin.com/linux/latest/source/include/linux/notifier.h).

#### `notifier.keyboard(callback)`

_notifier.keyboard()_ returns a new keyboard `notifier`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
and installs it in the system.
The `callback` function is called whenever a console keyboard event happens
(e.g., a key has been pressed or released).
This `callback` receives the following arguments:
* `event`: the available _events_ are defined by the
[notifier.kbd](https://github.com/luainkernel/lunatik#notifierkbd) table.
* `down`: `true`, if the key is pressed; `false`, if it is released.
* `shift`: `true`, if the shift key is held; `false`, otherwise.
* `key`: _keycode_ or _keysym_ depending on `event`.

The `callback` function might return the values defined by the
[notifier.notify](https://github.com/luainkernel/lunatik#notifiernotify) table.

#### `notifier.kbd`

_notifier.kbd_ is a table that exports
[KBD](https://elixir.bootlin.com/linux/latest/source/include/linux/notifier.h#L229)
flags to Lua.

* `"KEYCODE"`: keyboard _keycode_, called before any other.
* `"UNBOUND_KEYCODE"`: keyboard _keycode_ which is not bound to any other.
* `"UNICODE"`: keyboard unicode.
* `"KEYSYM"`: keyboard _keysym_.
* `"POST_KEYSYM"`: called after keyboard _keysym_ interpretation.

#### `notifier.notify`

_notifier.notify_ is a table that exports
[NOTIFY](https://elixir.bootlin.com/linux/latest/source/include/linux/notifier.h#L183)
flags to Lua.

* `"DONE"`: don't care.
* `"OK"`: suits me.
* `"BAD"`: bad/veto action.
* `"STOP"`: clean way to return from the notifier and stop further calls.

#### `notifier.delete(notfr)`, `notfr:delete()`

_notifier.delete()_ removes a `notifier` specified by the `notfr`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
from the system.

## Examples

### spyglass

[spyglass](https://github.com/luainkernel/lunatik/examples/spyglass.lua)
is a kernel script that implements a _keylogger_ inspired by the
[spy](https://github.com/jarun/spy) kernel module.
This kernel script logs the _keysym_ of the pressed keys in a device (`/dev/spyglass`).
If the _keysym_ is a printable character, `spyglass` logs the _keysym_ itself;
otherwise, it logs a mnemonic of the ASCII code, (e.g., `<del>` stands for `127`).

#### Usage

```
sudo cp examples/spyglass.lua /lib/modules/lua/ # installs spyglass
sudo sbin/lunatik --run spyglass    # runs spyglass
sudo tail -f /dev/spyglass          # prints the key log
sudo sh -c "echo 0 > /dev/spyglass" # disable the key logging
sudo sh -c "echo 1 > /dev/spyglass" # enable the key logging
```

### keylocker

[keylocker](https://github.com/luainkernel/lunatik/examples/keylocker.lua)
is a kernel script that implements
[Konami Code](https://en.wikipedia.org/wiki/Konami_Code)
for locking and unlocking the console keyboard.
When the user types `↑ ↑ ↓ ↓ ← → ← → LCTRL LALT`,
the keyboard will be _locked_; that is, the system will stop processing any key pressed
until the user types the same key sequence again.

#### Usage

```
sudo cp examples/keylocker.lua /lib/modules/lua/ # installs keylocker
sudo sbin/lunatik --run keylocker                # runs keylocker
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>   # locks keyboard
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>   # unlocks keyboard
```

## References

* [Scriptables Operating Systems with Lua](https://www.netbsd.org/~lneto/dls14.pdf)
* [Linux Network Scripting with Lua](https://legacy.netdevconf.info/0x14/session.html?talk-linux-network-scripting-with-lua)

