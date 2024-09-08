# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](driver.lua) (written in Lua =)) and a [command line tool](bin/lunatik)
to load and run scripts and manage runtime environments from the user space;
a [C API](#lunatik-c-api) to load and run scripts and manage runtime environments from the kernel;
and [Lua APIs](#lunatik-lua-apis) for binding kernel facilities to Lua scripts. 

Here is an example of a character device driver written in Lua using Lunatik
to generate random ASCII printable characters:
```Lua
-- /lib/modules/lua/passwd.lua
--
-- implements /dev/passwd for generate passwords
-- usage: $ sudo lunatik run passwd
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
sudo make install
sudo lunatik # execute Lunatik REPL
Lunatik 3.5  Copyright (C) 2023-2024 ring-0 Ltda.
> return 42 -- execute this line in the kernel
42
```

### lunatik

```Shell
usage: lunatik [load|unload|reload|status|list] [run|spawn|stop <script>]
```

* `load`: load Lunatik kernel modules
* `unload`: unload Lunatik kernel modules
* `reload`: reload Lunatik kernel modules
* `status`: show which Lunatik kernel modules are currently loaded
* `list`: show which runtime environments are currently running
* `run`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`
* `spawn`: create a new runtime environment and spawn a thread to run the script `/lib/modules/lua/<script>.lua`
* `stop`: stop the runtime environment created to run the script `<script>`
* `default`: start a _REPL (Read–Eval–Print Loop)_

## Lua Version

Lunatik 3.4 is based on
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
int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep);
```
_lunatik\_runtime()_ creates a new `runtime` environment then loads and runs the script
`/lib/modules/lua/<script>.lua` as the entry point for this environment.
It _must_ only be called from _process context_.
The `runtime` environment is a Lunatik object that holds
a [Lua state](https://www.lua.org/manual/5.4/manual.html#lua_State). 
Lunatik objects are special
Lua [userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
which also hold
a [lock type](https://docs.kernel.org/locking/locktypes.html) and
a [reference counter](https://www.kernel.org/doc/Documentation/kref.txt).
If `sleep` is _true_, _lunatik\_runtime()_ will use a
[mutex](https://docs.kernel.org/locking/mutex-design.html)
for locking the `runtime` environment and the
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html)
flag for allocating new memory later on on
[lunatik\_run()](https://github.com/luainkernel/lunatik#lunatik_run) calls.
Otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik\_runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api).
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
static lunatik_object_t *runtime;

static int __init mydevice_init(void)
{
	return lunatik_runtime(&runtime, "mydevice", true);
}

```

#### lunatik\_stop
```C
int lunatik_stop(lunatik_object_t *runtime);
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
void lunatik_run(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
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
	lunatik_object_t *runtime = (lunatik_object_t *)f->private_data;

	lunatik_run(runtime, l_read, ret, buf, len, off);
	return ret;
}
```

#### lunatik\_getobject
```C
void lunatik_getobject(lunatik_object_t *object);
```
_lunatik\_getobject()_ increments the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `object` (e.g., `runtime` environment).

#### lunatik\_put
```C
int lunatik_putobject(lunatik_object_t *object);
```
_lunatik\_putobject()_ decrements the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `object` (e.g., `runtime` environment).
If the `object` has been released, it returns `1`;
otherwise, it returns `0`.

#### lunatik\_toruntime
```C
lunatik_object_t *lunatik_toruntime(lua_State *L);
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
It returns a Lunatik object representing the `runtime` environment.
If `sleep` is _true_ or omitted, it will use a [mutex](https://docs.kernel.org/locking/mutex-design.html)
and
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html);
otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik.runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api).

#### `runtime:stop()`

_runtime:stop()_
[stops](https://github.com/luainkernel/lunatik#lunatik_stop)
the `runtime` environment and clear its reference from the runtime object.

#### `runtime:resume([obj1, ...])`

_runtime:resume()_
resumes the execution of a `runtime`.
The values `obj1, ...` are passed as the arguments to the function returned on the `runtime` creation.
If the `runtime` has yielded, `resume()` restarts it; the values `obj1, ...` are passed as the results from the yield.

### device

The `device` library provides support for writting
[character device drivers](https://static.lwn.net/images/pdf/LDD3/ch03.pdf)
in Lua.

#### `device.new(driver)`

_device.new()_ returns a new `device` object
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

#### `device.stop(dev)`, `dev:stop()`

_device.stop()_ removes a device `driver` specified by the `dev` object from the system.

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

#### `linux.schedule([timeout [, state]])`

_linux.schedule()_ sets the current task `state` and makes the it sleep until `timeout` milliseconds have elapsed.
If `timeout` is omitted, it uses `MAX_SCHEDULE_TIMEOUT`.
If `state` is omitted, it uses `task.INTERRUPTIBLE`.

#### `linux.task`

_linux.task_ is a table that exports
[task state](https://elixir.bootlin.com/linux/latest/source/include/linux/sched.h#L7v3)
flags to Lua.

* `"RUNNING"`: task is executing on a CPU or waiting to be executed.
* `"INTERRUPTIBLE"`: task is waiting for a signal or a resource (sleeping).
* `"UNINTERRUPTIBLE"`: behaves like "INTERRUPTIBLE" with the exception that signal will not wake up the task.
* `"KILLABLE"`: behaves like "UNINTERRUPTIBLE" with the exception that fatal signals will wake up the task.
* `"IDLE"`: behaves like "UNINTERRUPTIBLE" with the exception that it avoids the loadavg accounting.

#### `linux.time()`

_linux.time()_ returns the current time in nanoseconds since epoch.

#### `linux.errno`

_linux.errno_ is a table that exports
[\<uapi/asm-generic/errno-base.h\>](https://elixir.bootlin.com/linux/latest/source/include/uapi/asm-generic/errno-base.h)
flags to Lua.

* `"PERM"`: Operation not permitted.
* `"NOENT"`: No such file or directory.
* `"SRCH"`: No such process.
* `"INTR"`: Interrupted system call.
* `"IO"`: I/O error.
* `"NXIO"`:No such device or address.
* `"2BIG"`:, Argument list too long.
* `"NOEXEC"`: Exec format error.
* `"BADF"`: Bad file number.
* `"CHILD"`: No child processes.
* `"AGAIN"`: Try again.
* `"NOMEM"`: Out of memory.
* `"ACCES"`: Permission denied.
* `"FAULT"`: Bad address.
* `"NOTBLK"`: Block device required.
* `"BUSY"`: Device or resource busy.
* `"EXIST"`: File exists.
* `"XDEV"`: Cross-device link.
* `"NODEV"`: No such device.
* `"NOTDIR"`: Not a directory.
* `"ISDIR"`: Is a directory.
* `"INVAL"`: Invalid argument.
* `"NFILE"`: File table overflow.
* `"MFILE"`: Too many open files.
* `"NOTTY"`: Not a typewriter.
* `"TXTBSY"`: Text file busy.
* `"FBIG"`: File too large.
* `"NOSPC"`: No space left on device.
* `"SPIPE"`: Illegal seek.
* `"ROFS"`: Read-only file system.
* `"MLINK"`: Too many links.
* `"PIPE"`: Broken pipe.
* `"DOM"`: Math argument out of domain of func.
* `"RANGE"`: Math result not representable.

#### `linux.hton16(num)`

_linux.hton16()_ converts the host byte order to network byte order for a 16-bit integer.

#### `linux.hton32(num)`

_linux.hton32()_ converts the host byte order to network byte order for a 32-bit integer.

#### `linux.hton64(num)`

_linux.hton64()_ converts the host byte order to network byte order for a 64-bit integer.

#### `linux.ntoh16(num)`

_linux.ntoh16()_ converts the network byte order to host byte order for a 16-bit integer.

#### `linux.ntoh32(num)`

_linux.ntoh32()_ converts the network byte order to host byte order for a 32-bit integer.

#### `linux.ntoh64(num)`

_linux.ntoh64()_ converts the network byte order to host byte order for a 64-bit integer.

#### `linux.htobe16(num)`

_linux.htobe16()_ converts the host byte order to big-endian byte order for a 16-bit integer.

#### `linux.htobe32(num)`

_linux.htobe32()_ converts the host byte order to big-endian byte order for a 32-bit integer.

#### `linux.htobe64(num)`

_linux.htobe64()_ converts the host byte order to big-endian byte order for a 64-bit integer.

#### `linux.be16toh(num)`

_linux.be16toh()_ converts the big-endian byte order to host byte order for a 16-bit integer.

#### `linux.be32toh(num)`

_linux.be32toh()_ converts the big-endian byte order to host byte order for a 32-bit integer.

#### `linux.be64toh(num)`

_linux.be64toh()_ converts the big-endian byte order to host byte order for a 64-bit integer.

#### `linux.htole16(num)`

_linux.htole16()_ converts the host byte order to little-endian byte order for a 16-bit integer.

#### `linux.htole32(num)`

_linux.htole32()_ converts the host byte order to little-endian byte order for a 32-bit integer.

#### `linux.htole64(num)`

_linux.htole64()_ converts the host byte order to little-endian byte order for a 64-bit integer.

#### `linux.le16toh(num)`

_linux.le16toh()_ converts the little-endian byte order to host byte order for a 16-bit integer.

#### `linux.le32toh(num)`

_linux.le32toh()_ converts the little-endian byte order to host byte order for a 32-bit integer.

#### `linux.le64toh(num)`

_linux.le64toh()_ converts the little-endian byte order to host byte order for a 64-bit integer.

### notifier

The `notifier` library provides support for the kernel
[notifier chains](https://elixir.bootlin.com/linux/latest/source/include/linux/notifier.h).

#### `notifier.keyboard(callback)`

_notifier.keyboard()_ returns a new keyboard `notifier` object and installs it in the system.
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

#### `notifier.netdevice(callback)`

_notifier.netdevice()_ returns a new netdevice `notifier` object and installs it in the system.
The `callback` function is called whenever a console netdevice event happens
(e.g., a network interface has been connected or disconnected).
This `callback` receives the following arguments:
* `event`: the available _events_ are defined by the
[notifier.netdev](https://github.com/luainkernel/lunatik#notifiernetdev) table.
* `name`: the device name.

The `callback` function might return the values defined by the
[notifier.notify](https://github.com/luainkernel/lunatik#notifiernotify) table.

#### `notifier.netdev`

_notifier.netdev_ is a table that exports
[NETDEV](https://elixir.bootlin.com/linux/v6.3/source/include/linux/netdevice.h#L2812)
flags to Lua.

#### `notifier.notify`

_notifier.notify_ is a table that exports
[NOTIFY](https://elixir.bootlin.com/linux/latest/source/include/linux/notifier.h#L183)
flags to Lua.

* `"DONE"`: don't care.
* `"OK"`: suits me.
* `"BAD"`: bad/veto action.
* `"STOP"`: clean way to return from the notifier and stop further calls.

#### `notfr:delete()`

_notfr:delete()_ removes a `notifier` specified by the `notfr` object from the system.

### socket

The `socket` library provides support for the kernel
[networking handling](https://elixir.bootlin.com/linux/latest/source/include/linux/net.h).
This library was inspired by
[Chengzhi Tan](https://github.com/tcz717)'s
[GSoC project](https://summerofcode.withgoogle.com/archive/2018/projects/5993341447569408).

#### `socket.new(family, type, protocol)`

_socket.new()_ creates a new `socket` object.
This function receives the following arguments:
* `family`: the available _address families_ are defined by the
[socket.af](https://github.com/luainkernel/lunatik#socketaf) table.
* `sock`: the available _types_ are present on the
[socket.sock](https://github.com/luainkernel/lunatik#socketsock) table.
* `protocol`: the available _protocols_ are defined by the
[socket.ipproto](https://github.com/luainkernel/lunatik#socketipproto) table.

#### `socket.af`

_socket.af_ is a table that exports
[address families (AF)](https://elixir.bootlin.com/linux/latest/source/include/linux/socket.h#L187)
to Lua.

* `"UNSPEC"`: Unspecified.
* `"UNIX"`: Unix domain sockets.
* `"LOCAL"`: POSIX name for AF\_UNIX.
* `"INET"`: Internet IP Protocol.
* `"AX25"`: Amateur Radio AX.25.
* `"IPX"`: Novell IPX.
* `"APPLETALK"`: AppleTalk DDP.
* `"NETROM"`: Amateur Radio NET/ROM.
* `"BRIDGE"`: Multiprotocol bridge.
* `"ATMPVC"`: ATM PVCs.
* `"X25"`: Reserved for X.25 project.
* `"INET6"`: IP version 6.
* `"ROSE"`: Amateur Radio X.25 PLP.
* `"DEC"`: Reserved for DECnet project.
* `"NETBEUI"`: Reserved for 802.2LLC project.
* `"SECURITY"`: Security callback pseudo AF.
* `"KEY"`: PF\_KEY key management API.
* `"NETLINK"`: Netlink.
* `"ROUTE"`: Alias to emulate 4.4BSD.
* `"PACKET"`: Packet family.
* `"ASH"`: Ash.
* `"ECONET"`: Acorn Econet.
* `"ATMSVC"`: ATM SVCs.
* `"RDS"`: RDS sockets.
* `"SNA"`: Linux SNA Project (nutters!).
* `"IRDA"`: IRDA sockets.
* `"PPPOX"`: PPPoX sockets.
* `"WANPIPE"`: Wanpipe API Sockets.
* `"LLC"`: Linux LLC.
* `"IB"`: Native InfiniBand address.
* `"MPLS"`: MPLS.
* `"CAN"`: Controller Area Network.
* `"TIPC"`: TIPC sockets.
* `"BLUETOOTH"`: Bluetooth sockets.
* `"IUCV"`: IUCV sockets.
* `"RXRPC"`: RxRPC sockets.
* `"ISDN"`: mISDN sockets.
* `"PHONET"`: Phonet sockets.
* `"IEEE802154"`: IEEE802154 sockets.
* `"CAIF"`: CAIF sockets.
* `"ALG"`: Algorithm sockets.
* `"NFC"`: NFC sockets.
* `"VSOCK"`: vSockets.
* `"KCM"`: Kernel Connection Multiplexor.
* `"QIPCRTR"`: Qualcomm IPC Router.
* `"SMC"`: reserve number for PF\_SMC protocol family that reuses AF\_INET address family.
* `"XDP"`: XDP sockets.
* `"MCTP"`: Management component transport protocol.
* `"MAX"`: Maximum.

#### `socket.sock`

_socket.sock_ is a table that exports socket 
[types (SOCK)](https://elixir.bootlin.com/linux/latest/source/include/linux/net.h#L49):

* `"STREAM"`: stream (connection) socket.
* `"DGRAM"`: datagram (conn.less) socket.
* `"RAW"`: raw socket.
* `"RDM"`: reliably-delivered message.
* `"SEQPACKET"`: sequential packet socket.
* `"DCCP"`: Datagram Congestion Control Protocol socket.
* `"PACKET"`: linux specific way of getting packets at the dev level.

and [flags (SOCK)](https://elixir.bootlin.com/linux/latest/source/include/linux/net.h#L78):
* `"CLOEXEC"`: n/a.
* `"NONBLOCK"`: n/a.

#### `socket.ipproto`

_socket.ipproto_ is a table that exports
[IP protocols (IPPROTO)](https://elixir.bootlin.com/linux/latest/source/include/uapi/linux/in.h#L27)
to Lua.

* `"IP"`: Dummy protocol for TCP.
* `"ICMP"`: Internet Control Message Protocol.
* `"IGMP"`: Internet Group Management Protocol.
* `"IPIP"`: IPIP tunnels (older KA9Q tunnels use 94).
* `"TCP"`: Transmission Control Protocol.
* `"EGP"`: Exterior Gateway Protocol.
* `"PUP"`: PUP protocol.
* `"UDP"`: User Datagram Protocol.
* `"IDP"`: XNS IDP protocol.
* `"TP"`: SO Transport Protocol Class 4.
* `"DCCP"`: Datagram Congestion Control Protocol.
* `"IPV6"`: IPv6-in-IPv4 tunnelling.
* `"RSVP"`: RSVP Protocol.
* `"GRE"`: Cisco GRE tunnels (rfc 1701,1702).
* `"ESP"`: Encapsulation Security Payload protocol.
* `"AH"`: Authentication Header protocol.
* `"MTP"`: Multicast Transport Protocol.
* `"BEETPH"`: IP option pseudo header for BEET.
* `"ENCAP"`: Encapsulation Header.
* `"PIM"`: Protocol Independent Multicast.
* `"COMP"`: Compression Header Protocol.
* `"SCTP"`: Stream Control Transport Protocol.
* `"UDPLITE"`: UDP-Lite (RFC 3828).
* `"MPLS"`: MPLS in IP (RFC 4023).
* `"ETHERNET"`: Ethernet-within-IPv6 Encapsulation.
* `"RAW"`: Raw IP packets.
* `"MPTCP"`: Multipath TCP connection.

#### `sock:close()`

_sock:close()_ removes `sock` object from the system.

#### `sock:send(message, [addr [, port]])`

_sock:send()_ sends a string `message` through the socket `sock`.
If the `sock` address family is `af.INET`, then it expects the following arguments:
* `addr`: `integer` describing the destination IPv4 address.
* `port`: `integer` describing the destination IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the destination address.

#### `sock:receive(length, [flags [, from]])`

_sock:receive()_ receives a string with up to `length` bytes through the socket `sock`.
The available _message flags_ are defined by the
[socket.msg](https://github.com/luainkernel/lunatik#socketmsg) table.
If `from` is `true`, it returns the received message followed by the peer's address.
Otherwise, it returns only the received message.

#### `socket.msg`

_socket.msg_ is a table that exports
[message flags](https://elixir.bootlin.com/linux/latest/source/include/linux/socket.h#L298)
to Lua.

* `"OOB"`: n/a.
* `"PEEK"`: n/a.
* `"DONTROUTE"`: n/a.
* `"TRYHARD"`: Synonym for `"DONTROUTE"` for DECnet.
* `"CTRUNC"`: n/a.
* `"PROBE"`: Do not send. Only probe path f.e. for MTU.
* `"TRUNC"`: n/a.
* `"DONTWAIT"`: Nonblocking io.
* `"EOR"`: End of record.
* `"WAITALL"`: Wait for a full request.
* `"FIN"`: n/a.
* `"SYN"`: n/a.
* `"CONFIRM"`: Confirm path validity.
* `"RST"`: n/a.
* `"ERRQUEUE"`: Fetch message from error queue.
* `"NOSIGNAL"`: Do not generate SIGPIPE.
* `"MORE"`: Sender will send more.
* `"WAITFORONE"`: recvmmsg(): block until 1+ packets avail.
* `"SENDPAGE_NOPOLICY"`: sendpage() internal: do no apply policy.
* `"SENDPAGE_NOTLAST"`: sendpage() internal: not the last page.
* `"BATCH"`: sendmmsg(): more messages coming.
* `"EOF"`: n/a.
* `"NO_SHARED_FRAGS"`: sendpage() internal: page frags are not shared.
* `"SENDPAGE_DECRYPTED"`: sendpage() internal: page may carry plain text and require encryption.
* `"ZEROCOPY"`: Use user data in kernel path.
* `"FASTOPEN"`: Send data in TCP SYN.
* `"CMSG_CLOEXEC"`: Set close\_on\_exec for file descriptor received through SCM\_RIGHTS.

#### `sock:bind(addr [, port])`

_sock:bind()_ binds the socket `sock` to a given address.
If the `sock` address family is `af.INET`, then it expects the following arguments:
* `addr`: `integer` describing host IPv4 address.
* `port`: `integer` describing host IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing host address.

#### `sock:listen([backlog])`

_sock:listen()_ moves the socket `sock` to listening state.
* `backlog`: pending connections queue size.
If omitted, it uses
[SOMAXCONN](https://elixir.bootlin.com/linux/latest/source/include/linux/socket.h#L296)
as default.

#### `sock:accept([flags])`

_sock:accept()_ accepts a connection on socket `sock`.
It returns a new `socket` object.
The available _flags_ are present on the
[socket.sock](https://github.com/luainkernel/lunatik#socketsock) table.

#### `sock:connect(addr [, port] [, flags])`

_sock:connect()_ connects the socket `sock` to the address `addr`.
If the `sock` address family is `af.INET`, then it expects the following arguments:
* `addr`: `integer` describing the destination IPv4 address.
* `port`: `integer` describing the destination IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the destination address.

The available _flags_ are present on the
[socket.sock](https://github.com/luainkernel/lunatik#socketsock) table.

For datagram sockets, `addr` is the address to which datagrams are sent
by default, and the only address from which datagrams are received.
For stream sockets, attempts to connect to `addr`.

#### `sock:getsockname()`

_sock:getsockname()_ get the address which the socket `sock` is bound.
If the `sock` address family is `af.INET`, then it returns the following:
* `addr`: `integer` describing the bounded IPv4 address.
* `port`: `integer` describing the bounded IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the bounded address.

#### `sock:getpeername()`

_sock:getpeername()_ get the address which the socket `sock` is connected.
If the `sock` address family is `af.INET`, then it returns the following:
* `addr`: `integer` describing the peer's IPv4 address.
* `port`: `integer` describing the peer's IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the peer's address.

### socket.inet

The `socket.inet` library provides support for high-level IPv4 sockets.

#### `inet.tcp()`

_inet.tcp()_ creates a new `socket` using
[af.INET](https://github.com/luainkernel/lunatik#socketaf) address family,
[sock.STREAM](https://github.com/luainkernel/lunatik#socketsock) type
and
[ipproto.TCP](https://github.com/luainkernel/lunatik#socketipproto) protocol.
It overrides `socket` methods to use addresses as _numbers-and-dots notation_
(e.g., `"127.0.0.1"`), instead of integers.

#### `inet.udp()`

_inet.udp()_ creates a new `socket` using
[af.INET](https://github.com/luainkernel/lunatik#socketaf) address family,
[sock.DGRAM](https://github.com/luainkernel/lunatik#socketsock) type
and
[ipproto.UDP](https://github.com/luainkernel/lunatik#socketipproto) protocol.
It overrides `socket` methods to use addresses as _numbers-and-dots notation_
(e.g., `"127.0.0.1"`), instead of integers.

##### `udp:receivefrom(length [, flags])`

_udp:receivefrom()_ is just an alias to `sock:receive(length, flags, true)`.

### rcu

The `rcu` library provides support for the kernel
[Read-copy update (RCU)](https://lwn.net/Articles/262464/)
synchronization mechanism.
This library was inspired by
[Caio Messias](https://github.com/cmessias)'
[GSoC project](https://summerofcode.withgoogle.com/archive/2018/projects/5736202426646528).

#### `rcu.table([size])`

_rcu.table()_ creates a new `rcu.table` object
which binds the kernel [generic hash table](https://lwn.net/Articles/510202/).
This function receives as argument the number of buckets rounded up to the next power of 2.
The default size is `1024`.
Key must be a string and value must be a Lunatik object or nil.

### thread

The `thread` library provides support for the
[kernel thread primitives](https://lwn.net/Articles/65178/).

#### `thread.run(runtime, name)`

_thread.run()_ creates a new `thread` object and wakes it up.
This function receives the following arguments:
* `runtime`: the
[runtime environment](https://github.com/luainkernel/lunatik#lunatikruntimescript--sleep)
for running a task in the created kernel thread.
The task must be specified by returning a function on the script loaded 
in the `runtime` environment.
* `name`: string representing the name for the thread (e.g., as shown on `ps`). 

#### `thread.shouldstop()`

_thread.shouldstop()_ returns `true` if
[thread.stop()](https://github.com/luainkernel/lunatik#threadstopthrd-thrdstop)
was called; otherwise, it returns `false`.

#### `thread.current()`

_thread.current()_ returns a `thread` object representing the current task.

#### `thrd:stop()`

_thrd:stop()_ sets
[thread.shouldstop()](https://github.com/luainkernel/lunatik#threadshouldstop)
on the thread `thrd` to return true, wakes `thrd`, and waits for it to exit.

#### `thrd:task()`

_thrd:task()_ returns a table containing the task information of this `thread`
(e.g., "cpu", "command", "pid" and "tgid").

### fib

The `fib` library provides support for the
[kernel Forwarding Information Base](https://thermalcircle.de/doku.php?id=blog:linux:routing_decisions_in_the_linux_kernel_1_lookup_packet_flow).

#### `fib.newrule(table, priority)`

_fib.newrule()_ binds the kernel
[fib_nl_newrule](https://elixir.bootlin.com/linux/latest/source/include/net/fib_rules.h#L182)
API;
it creates a new FIB rule that matches the specified routing _table_
with the specified _priorioty_.
This function is similar to the user-space command
[ip rule add](https://datahacker.blog/industry/technology-menu/networking/iptables/follow-the-ip-rules)
provided by [iproute2](https://wiki.linuxfoundation.org/networking/iproute2).

#### `fib.delrule(table, priority)`

_fib.delrule()_ binds the kernel
[fib_nl_delrule](https://elixir.bootlin.com/linux/latest/source/include/net/fib_rules.h#L184)
API;
it removes a FIB rule that matches the specified routing _table_
with the specified _priorioty_.
This function is similar to the user-space command
[ip rule del](https://datahacker.blog/industry/technology-menu/networking/iptables/follow-the-ip-rules)
provided by [iproute2](https://wiki.linuxfoundation.org/networking/iproute2).

### data

The `data` library provides support for binding the system memory to Lua.

#### `data.new(size)`

_data.new()_ creates a new `data` object which allocates `size` bytes.

#### `d:getnumber(offset)`

_d:getnumber()_ extracts a [lua\_Integer](https://www.lua.org/manual/5.4/manual.html#lua_Integer)
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setnumber(offset, number)`

_d:setnumber()_ insert a [lua\_Integer](https://www.lua.org/manual/5.4/manual.html#lua_Integer)
`number` into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getbyte(offset)`

_d:getbyte()_ extracts a byte
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setbyte(offset, byte)`

_d:setbyte()_ insert a byte
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getstring(offset[, length])`

_d:getstring()_ extracts a string with `length` bytes
from the memory referenced by a `data` object and a byte `offset`,
starting from zero. If `length` is omitted, it extracts all bytes 
from `offset` to the end of the `data`.

#### `d:setstring(offset, s)`

_d:setstring()_ insert the string `s`
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getint8(offset)`

_d:getint8(d, offset)_ extracts a signed 8-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setint8(offset, number)`

_d:setint8()_ inserts a signed 8-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getuint8(offset)`

_d:getuint8()_ extracts an unsigned 8-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setuint8(offset, number)`

_d:setuint8()_ inserts an unsigned 8-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getint16(offset)`

_d:getint16()_ extracts a signed 16-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setint16(offset, number)`

_d:setint16()_ inserts a signed 16-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getuint16(offset)`

_d:getuint16()_ extracts an unsigned 16-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setuint16(offset, number)`

_d:setuint16()_ inserts an unsigned 16-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getint32(offset)`

_d:getint32()_ extracts a signed 32-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setint32(offset, number)`

_d:setint32()_ inserts a signed 32-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getuint32(offset)`

_d:getuint32()_ extracts an unsigned 32-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setuint32(offset, number)`

_d:setuint32()_ inserts an unsigned 32-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:getint64(offset)`

_d:getint64()_ extracts a signed 64-bit integer
from the memory referenced by a `data` object and a byte `offset`,
starting from zero.

#### `d:setint64(offset, number)`

_d:setint64()_ inserts a signed 64-bit number
into the memory referenced by a `data` object and a byte `offset`,
starting from zero.

### probe

The `probe` library provides support for
[kernel probes](https://docs.kernel.org/trace/kprobes.html).

#### `probe.new(symbol|address, handlers)`

_probe.new()_ returns a new `probe` object for monitoring a kernel `symbol` (string) or `address` (light userdata)
and installs its `handlers` in the system.
The `handler` **must** be defined as a table containing the following field:
* `pre`: function to be called before the probed instruction.
It receives the `symbol` or `address`,
followed by a closure that may be called to
[show the CPU registers and stack](https://elixir.bootlin.com/linux/v5.6.19/source/include/linux/sched/debug.h#L26)
in the system log.
* `post`: function to be called after the probed instruction.
It receives the `symbol` or `address`,
followed by a closure that may be called to
[show the CPU registers and stack](https://elixir.bootlin.com/linux/v5.6.19/source/include/linux/sched/debug.h#L26)
in the system log.

#### `p:stop()`

_p:stop()_ removes the `probe` handlers from the system.

#### `p:enable(bool)`

_p:enable()_ enables or disables the `probe` handlers, accordingly to `bool`.

### syscall

The `syscall` library provides support for system call addresses and numbers.

#### `syscall.address(number)`

_syscall.address()_ returns the system call address (light userdata) referenced by the given `number`.

#### `syscall.number(name)`

_syscall.number()_ returns the system call number referenced by the given `name`.

### syscall.table

The `syscall.table` library provides support for translating system call names to addresses (light userdata).

### xdp

The `xdp` library provides support for the kernel
[eXpress Data Path (XDP)](https://prototype-kernel.readthedocs.io/en/latest/networking/XDP/)
subsystem.
This library was inspired by
[Victor Nogueira](https://github.com/VictorNogueiraRio/linux)'s
[GSoC project](https://victornogueirario.github.io/xdplua/).

#### `xdp.attach(callback)`

_xdp.attach()_ registers a `callback` function to the current `runtime`
to be called from an XDP/eBPF program whenever it calls
[bpf_luaxdp_run](lib/luaxdp.c#L106)
[kfunc](https://docs.kernel.org/bpf/kfuncs.html).
This `callback` receives the following arguments:
* `buffer`: a `data` object representing the network buffer.
* `argument`: a `data` object containing the argument passed by the XDP/eBPF program.

The `callback` function might return the values defined by the
[xdp.action](https://github.com/luainkernel/lunatik#xdpaction) table.

#### `xdp.detach()`

_xdp.detach()_ unregisters the `callback` associated with the current `runtime`, if any.

#### `xdp.action`

_xdp.action_ is a table that exports
[xdp_action](https://elixir.bootlin.com/linux/v6.4/source/include/uapi/linux/bpf.h#L6187)
flags to Lua.

* `"ABORTED"`: n/a.
* `"DROP"`: n/a.
* `"PASS"`: n/a.
* `"TX"`: n/a.
* `"REDIRECT"`: n/a.

### xtable

The `xtable` library provides support for developing netfilter [xtable extensions](https://inai.de/projects/xtables-addons/).

#### `xtable.match(opts)`

_xtable.match()_ returns a new [xtable](https://inai.de/projects/xtables-addons/) object for match extensions.
This function receives the following arguments:
* `opts`: a table containing the following fields:
  * `name`: string representing the xtable extension name.
  * `revision`: integer representing the xtable extension revision.
  * `family`: address family, one of [netfilter.family](https://github.com/luainkernel/lunatik#netfilterfamily).
  * `proto`: protocol number, one of [socket.ipproto](https://github.com/luainkernel/lunatik#socketipproto).
  * `hooks` : hook to attach the extension to, one value from either of the hooks table - [netfilter.inet_hooks](https://github.com/luainkernel/lunatik#netfilterinet_hooks), [netfilter.bridge_hooks](https://github.com/luainkernel/lunatik#netfilterbridge_hooks) and [netfilter.arp_hooks](https://github.com/luainkernel/lunatik#netfilterarp_hooks) (Note: [netfilter.netdev_hooks](https://github.com/luainkernel/lunatik#netfilternetdev_hooks) is not available for legacy x_tables). (E.g - `1 << inet_hooks.LOCAL_OUT`).
  * `match` : function to be called for matching packets. It receives the following arguments:
	* `skb` (readonly): a `data` object representing the socket buffer.
	* `par`: a table containing `hotdrop`, `thoff` (transport header offset) and `fragoff` (fragment offset) fields.
    * `userargs` : a lua string passed from the userspace xtable module.
    * The function must return `true` if the packet matches the extension; otherwise, it must return `false`.
  * `checkentry`: function to be called for checking the entry. This function receives `userargs` as its argument.
  * `destroy`: function to be called for destroying the xtable extension. This function receives `userargs` as its argument.

#### `xtable.target(opts)`

_xtable.target()_ returns a new [xtable](https://inai.de/projects/xtables-addons/) object for target extension.
This function receives the following arguments:
* `opts`: a table containing the following fields:
  * `name`: string representing the xtable extension name.
  * `revision`: integer representing the xtable extension revision.
  * `family`: address family, one of [netfilter.family](https://github.com/luainkernel/lunatik#netfilterfamily).
  * `proto`: protocol number, one of [socket.ipproto](https://github.com/luainkernel/lunatik#socketipproto).
  * `hooks` : hook to attach the extension to, one value from either of the hooks table - [netfilter.inet_hooks](https://github.com/luainkernel/lunatik#netfilterinet_hooks), [netfilter.bridge_hooks](https://github.com/luainkernel/lunatik#netfilterbridge_hooks) and [netfilter.arp_hooks](https://github.com/luainkernel/lunatik#netfilterarp_hooks) (Note: [netfilter.netdev_hooks](https://github.com/luainkernel/lunatik#netfilternetdev_hooks) is not available for legacy x_tables). (E.g - `1 << inet_hooks.LOCAL_OUT`).
  * `target` : function to be called for targeting packets. It receives the following arguments:
    * `skb`: a `data` object representing the socket buffer.
    * `par` (readonly): a table containing `hotdrop`, `thoff` (transport header offset) and `fragoff` (fragment offset) fields.
    * `userargs` : a lua string passed from the userspace xtable module.
    * The function must return one of the values defined by the [netfilter.action](https://github.com/luainkernel/lunatik#netfilteraction) table.
  * `checkentry`: function to be called for checking the entry. This function receives `userargs` as its argument.
  * `destroy`: function to be called for destroying the xtable extension. This function receives `userargs` as its argument.

### netfilter

The `netfilter` library provides support for the [new netfilter hook](https://www.netfilter.org/documentation/HOWTO/netfilter-hacking-HOWTO-4.html#ss4.6) system.

#### `netfilter.register(ops)`

_netfilter.register()_ registers a new netfilter hook with the given `ops` table.
This function receives the following arguments:
* `ops`: a table containing the following fields:
  * `pf`: protocol family, one of [netfilter.family](https://github.com/luainkernel/lunatik#netfilterfamily)
  * `hooknum`:	hook to attach the filter to, one value from either of the hooks table - [netfilter.inet_hooks](https://github.com/luainkernel/lunatik#netfilterinet_hooks), [netfilter.bridge_hooks](https://github.com/luainkernel/lunatik#netfilterbridge_hooks), [netfilter.arp_hooks](https://github.com/luainkernel/lunatik#netfilterarp_hooks) and [netfilter.netdev_hooks](https://github.com/luainkernel/lunatik#netfilternetdev_hooks). (E.g - `inet_hooks.LOCAL_OUT + 11`).
  * `priority`:	priority of the hook. One of the values from the [netfilter.ip_priority](https://github.com/luainkernel/lunatik#netfilterip_priority) or [netfilter.bridge_priority](https://github.com/luainkernel/lunatik#netfilterbridge_priority) tables.
  * `hook`: function to be called for the hook. It receives the following arguments:
	* `skb`: a `data` object representing the socket buffer.
	* The function must return one of the values defined by the [netfilter.action](https://github.com/luainkernel/lunatik#netfilteraction).

#### `netfilter.family`

_netfilter.family_ is a table that exports
address families to Lua.

* `"UNSPEC"`: Unspecified.
* `"INET"`: Internet Protocol version 4.
* `"IPV4"`: Internet Protocol version 4.
* `"IPV6"`: Internet Protocol version 6.
* `"ARP"`: Address Resolution Protocol.
* `"NETDEV"`: Device ingress and egress path
* `"BRIDGE"`: Ethernet Bridge.

#### `netfilter.action`

_netfilter.action_ is a table that exports
netfilter actions to Lua.

* `"DROP"`: `NF_DROP`. The packet is dropped. It is not forwarded, processed, or seen by any other network layer.
* `"ACCEPT"`: `NF_ACCEPT`. The packet is accepted and passed to the next step in the network processing chain.
* `"STOLEN"`: `NF_STOLEN`. The packet is taken by the handler, and processing stops.
* `"QUEUE"`: `NF_QUEUE`. The packet is queued for user-space processing.
* `"REPEAT"`: `NF_REPEAT`. The packet is sent through the hook chain again. 
* `"STOP"`: `NF_STOP`. Processing of the packet stops.
* `"CONTINUE"`: `XT_CONTINUE`. Return the packet should continue traversing the rules within the same table.
* `"RETURN"`: `XT_RETURN`. Return the packet to the previous chain.

#### `netfilter.inet_hooks`

_netfilter.inet_hooks_ is a table that exports
inet netfilter hooks to Lua.

* `"PRE_ROUTING"`: `NF_INET_PRE_ROUTING`. The packet is received by the network stack.
* `"LOCAL_IN"`: `NF_INET_LOCAL_IN`. The packet is destined for the local system.
* `"FORWARD"`: `NF_INET_FORWARD`. The packet is to be forwarded to another host.
* `"LOCAL_OUT"`: `NF_INET_LOCAL_OUT`. The packet is generated by the local system.
* `"POST_ROUTING"`: `NF_INET_POST_ROUTING`. The packet is about to be sent out.

#### `netfilter.bridge_hooks`

_netfilter.bridge_hooks_ is a table that exports
bridge netfilter hooks to Lua.

* `"PRE_ROUTING"`: `NF_BR_PRE_ROUTING`. First hook invoked, runs before forward database is consulted.
* `"LOCAL_IN"`: `NF_BR_LOCAL_IN`. Invoked for packets destined for the machine where the bridge was configured on.
* `"FORWARD"`: `NF_BR_FORWARD`. Called for frames that are bridged to a different port of the same logical bridge device. 
* `"LOCAL_OUT"`: `NF_BR_LOCAL_OUT`. Called for locally originating packets that will be transmitted via the bridge.
* `"POST_ROUTING"`: `NF_BR_POST_ROUTING`. Called for all locally generated packets and all bridged packets

#### `netfilter.arp_hooks`

_netfilter.arp_hooks_ is a table that exports
arp netfilter hooks to Lua.

* `"IN"`: `NF_ARP_IN`. The packet is received by the network stack.
* `"OUT"`: `NF_ARP_OUT`. The packet is generated by the local system.
* `"FORWARD"`: `NF_ARP_FORWARD`. The packet is to be forwarded to another host.

#### `netfilter.netdev_hooks`

_netfilter.netdev_hooks_ is a table that exports
netdev netfilter hooks to Lua.

* `"INGRESS"`: `NF_NETDEV_INGRESS`. The packet is received by the network stack.
* `"EGRESS"`: `NF_NETDEV_EGRESS`. The packet is generated by the local system.

#### `netfilter.ip_priority`

_netfilter.ip_priority_ is a table that exports
netfilter IPv4/IPv6 priority levels to Lua.

* `"FIRST"`: `NF_IP_PRI_FIRST`
* `"RAW_BEFORE_DEFRAG"`: `NF_IP_PRI_RAW_BEFORE_DEFRAG`
* `"CONNTRACK_DEFRAG"`: `NF_IP_PRI_CONNTRACK_DEFRAG`
* `"RAW"`: `NF_IP_PRI_RAW`
* `"SELINUX_FIRST"`: `NF_IP_PRI_SELINUX_FIRST`
* `"CONNTRACK"`: `NF_IP_PRI_CONNTRACK`
* `"MANGLE"`: `NF_IP_PRI_MANGLE`
* `"NAT_DST"`: `NF_IP_PRI_NAT_DST`
* `"FILTER"`: `NF_IP_PRI_FILTER`
* `"SECURITY"`: `NF_IP_PRI_SECURITY`
* `"NAT_SRC"`: `NF_IP_PRI_NAT_SRC`
* `"SELINUX_LAST"`: `NF_IP_PRI_SELINUX_LAST`
* `"CONNTRACK_HELPER"`: `NF_IP_PRI_CONNTRACK_HELPER`
* `"LAST"`: `NF_IP_PRI_LAST`

#### `netfilter.bridge_priority`

_netfilter.bridge_priority_ is a table that exports
netfilter bridge priority levels to Lua.

* `"FIRST"`: `NF_BR_PRI_FIRST`
* `"NAT_DST_BRIDGED"`: `NF_BR_PRI_NAT_DST_BRIDGED`
* `"FILTER_BRIDGED"`: `NF_BR_PRI_FILTER_BRIDGED`
* `"BRNF"`: `NF_BR_PRI_BRNF`
* `"NAT_DST_OTHER"`: `NF_BR_PRI_NAT_DST_OTHER`
* `"FILTER_OTHER"`: `NF_BR_PRI_FILTER_OTHER`
* `"NAT_SRC"`: `NF_BR_PRI_NAT_SRC`
* `"LAST"`: `NF_BR_PRI_LAST`

### luaxt

The `luaxt` [userspace library](usr/lib/xtable) provides support for generating userspace code for [xtable extensions](https://inai.de/projects/xtables-addons/).

To build the library, the following steps are required:

1. Go to `usr/lib/xtable` and create a `libxt_<ext_name>.lua` file.
2. Register your callbacks for the xtable extension by importing the library (`luaxt`) in the created file.
3. Run `LUAXTABLE_MODULE=<ext_name> make` to build the extension and `LUAXTABLE_MODULE=<ext_name> make install` (as root) to install the userspace plugin to the system.

Now load the extension normally using `iptables`.

#### `luaxt.match(opts)`

_luaxt.match()_ returns a new [luaxt](https://inai.de/projects/xtables-addons/) object for match extensions.
This function receives the following arguments:
* `opts`: a table containing the following fields:
  * `revision`: integer representing the xtable extension revision (**must** be same as used in corresponding kernel extension).
  * `family`: address family, one of [luaxt.family](https://github.com/luainkernel/lunatik#luaxtfamily)
  * `help`: function to be called for displaying help message for the extension.
  * `init`: function to be called for initializing the extension. This function receives an `par` table that can be used to set `userargs`. (`par.userargs = "mydata"`)
  * `print`: function to be called for printing the arguments. This function recevies `userargs` set by the `init` or `parse` function.
  * `save`: function to be called for saving the arguments. This function recevies `userargs` set by the `init` or `parse` function.
  * `parse`: function to be called for parsing the command line arguments. This function receives an `par` table that can be used to set `userargs` and `flags`. (`par.userargs = "mydata"`)
  * `final_check`: function to be called for final checking of the arguments. This function receives `flags` set by the `parse` function.

#### `luaxt.target(opts)`

_luaxt.target()_ returns a new [luaxt](https://inai.de/projects/xtables-addons/) object for target extensions.
This function receives the following arguments:
* `opts`: a table containing the following fields:
  * `revision`: integer representing the xtable extension revision (**must** be same as used in corresponding kernel extension).
  * `family`: address family, one of [luaxt.family](https://github.com/luainkernel/lunatik#luaxtfamily)
  * `help`: function to be called for displaying help message for the extension.
  * `init`: function to be called for initializing the extension. This function receives an `par` table that can be used to set `userargs`. (`par.userargs = "mydata"`)
  * `print`: function to be called for printing the arguments. This function recevies `userargs` set by the `init` or `parse` function.
  * `save`: function to be called for saving the arguments. This function recevies `userargs` set by the `init` or `parse` function.
  * `parse`: function to be called for parsing the command line arguments. This function receives an `par` table that can be used to set `userargs` and `flags`. (`par.userargs = "mydata"`)
  * `final_check`: function to be called for final checking of the arguments. This function receives `flags` set by the `parse` function.

#### `luaxt.family`

_luaxt.family_ is a table that exports
address families to Lua.

* `"UNSPEC"`: Unspecified.
* `"INET"`: Internet Protocol version 4.
* `"IPV4"`: Internet Protocol version 4.
* `"IPV6"`: Internet Protocol version 6.
* `"ARP"`: Address Resolution Protocol.
* `"NETDEV"`: Device ingress and egress path
* `"BRIDGE"`: Ethernet Bridge.

### `completion`

The `completion` library provides support for the [kernel completion primitives](https://docs.kernel.org/scheduler/completion.html).

Task completion is a synchronization mechanism used to coordinate the execution of multiple threads, similar to `pthread_barrier`, it allows threads to wait for a specific event to occur before proceeding, ensuring certain tasks are complete in a race-free manner.

#### `completion.new()`

_completion.new()_ creates a new `completion` object.

#### `c:complete()`

_c:complete()_ signals a single thread waiting on this completion.

#### `c:wait([timeout])`

_c:wait()_ waits for completion of a task until the specified timeout expires.
The timeout is specified in milliseconds. If the `timeout` parameter is omitted, it waits indefinitely. Passing a timeout value less than zero results in undefined behavior.
Threads waiting for events can be interrupted by signals, for example, such as when `thread.stop` is invoked.
Therefore, this function can return in three ways:
* If it succeeds, it returns `true`
* If the timeout is reached, it returns `nil, "timeout"`
* If the task is interrupted, it returns `nil, "interrupt"`

# Examples

### spyglass

[spyglass](examples/spyglass.lua)
is a kernel script that implements a _keylogger_ inspired by the
[spy](https://github.com/jarun/spy) kernel module.
This kernel script logs the _keysym_ of the pressed keys in a device (`/dev/spyglass`).
If the _keysym_ is a printable character, `spyglass` logs the _keysym_ itself;
otherwise, it logs a mnemonic of the ASCII code, (e.g., `<del>` stands for `127`).

#### Usage

```
sudo make examples_install          # installs examples
sudo lunatik run examples/spyglass  # runs spyglass
sudo tail -f /dev/spyglass          # prints the key log
sudo sh -c "echo 'enable=false' > /dev/spyglass"       # disable the key logging
sudo sh -c "echo 'enable=true' > /dev/spyglass"        # enable the key logging
sudo sh -c "echo 'net=127.0.0.1:1337' > /dev/spyglass" # enable network support
nc -lu 127.0.0.1 1337 &             # listen to UDP 127.0.0.1:1337
sudo tail -f /dev/spyglass          # sends the key log through the network
```

### keylocker

[keylocker](examples/keylocker.lua)
is a kernel script that implements
[Konami Code](https://en.wikipedia.org/wiki/Konami_Code)
for locking and unlocking the console keyboard.
When the user types `↑ ↑ ↓ ↓ ← → ← → LCTRL LALT`,
the keyboard will be _locked_; that is, the system will stop processing any key pressed
until the user types the same key sequence again.

#### Usage

```
sudo make examples_install                     # installs examples
sudo lunatik run examples/keylocker            # runs keylocker
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT> # locks keyboard
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT> # unlocks keyboard
```

### tap

[tap](examples/tap.lua)
is a kernel script that implements a _sniffer_ using `AF_PACKET` socket.
It prints destination and source MAC addresses followed by Ethernet type and the frame size.

#### Usage

```
sudo make examples_install    # installs examples
sudo lunatik run examples/tap # runs tap
cat /dev/tap
```

### shared

[shared](examples/shared.lua)
is a kernel script that implements an in-memory key-value store using
[rcu](https://github.com/luainkernel/lunatik#rcu),
[data](https://github.com/luainkernel/lunatik#data),
[socket](https://github.com/luainkernel/lunatik#socket) and
[thread](https://github.com/luainkernel/lunatik#thread).

#### Usage

```
sudo make examples_install         # installs examples
sudo lunatik spawn examples/shared # spawns shared
nc 127.0.0.1 90                    # connects to shared
foo=bar                            # assigns "bar" to foo
foo                                # retrieves foo
bar
^C                                 # finishes the connection
```

### echod

[echod](examples/echod)
is an echo server implemented as kernel scripts.

#### Usage

```
sudo make examples_install               # installs examples
sudo lunatik spawn examples/echod/daemon # runs echod
nc 127.0.0.1 1337
hello kernel!
hello kernel!
```

### systrack

[systrack](examples/systrack.lua)
is a kernel script that implements a device driver to monitor system calls.
It prints the amount of times each [system call](examples/systrack.lua#L29)
was called since the driver has been installed.

#### Usage

```
sudo make examples_install         # installs examples
sudo lunatik run examples/systrack # runs systracker
cat /dev/systrack
writev: 0
close: 1927
write: 1085
openat: 2036
read: 4131
readv: 0
```

### filter

[filter](examples/filter) is a kernel extension composed by
a XDP/eBPF program to filter HTTPS sessions and
a Lua kernel script to filter [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) TLS extension.
This kernel extension drops any HTTPS request destinated to a
[blacklisted](examples/filter/sni.lua#L35) server.

#### Usage

```
sudo make examples_install                   # installs examples
cd examples/filter
make                                         # builds the XDP/eBPF program
sudo lunatik run examples/filter/sni false   # runs the Lua kernel script
sudo xdp-loader load -m skb <ifname> https.o # loads the XDP/eBPF program
```

### dnsblock

[dnsblock](examples/dnsblock) is a kernel script that uses the lunatik xtable library to filter DNS packets. 
This script drops any outbound DNS packet with question matching the blacklist provided by the user.

#### Usage

1. Using legacy iptables
```
sudo make examples_install              # installs examples
cd examples/dnsblock
make                                    # builds the userspace extension for netfilter
sudo make install   					# installs the extension to Xtables directory
sudo lunatik run examples/dnsblock/dnsblock false	# runs the Lua kernel script
sudo iptables -A OUTPUT -m dnsblock -j DROP     	# this initiates the netfilter framework to load our extension
```

2. Using new netfilter framework ([luanetfilter](https://github.com/luainkernel/lunatik#netfilter))

```
sudo make examples_install              # installs examples
sudo lunatik run examples/dnsblock/nf_dnsblock false	# runs the Lua kernel script
```

### dnsdoctor

[dnsdoctor](examples/dnsdoctor) is a kernel script that uses the lunatik xtable library to change the DNS response 
from Public IP to a Private IP if the destination IP matches the one provided by the user. For example, if the user
wants to change the DNS response from `192.168.10.1` to `10.1.2.3` for the domain `lunatik.com` if the query is being sent to `10.1.1.2` (a private client), this script can be used.

#### Usage

1. Using legacy iptables
```
sudo make examples_install              # installs examples
cd examples/dnsdoctor
setup.sh                                # sets up the environment

# test the setup, a response with IP 192.168.10.1 should be returned
dig lunatik.com

# run the Lua kernel script
sudo lunatik run examples/dnsdoctor/dnsdoctor false

# build and install the userspace extension for netfilter
make
sudo make install

# add rule to the mangle table
sudo iptables -t mangle -A PREROUTING -p udp --sport 53 -j dnsdoctor

# test the setup, a response with IP 10.1.2.3 should be returned
dig lunatik.com

# cleanup
sudo iptables -t mangle -D PREROUTING -p udp --sport 53 -j dnsdoctor # remove the rule
sudo lunatik unload
cleanup.sh
```

2. Using new netfilter framework ([luanetfilter](https://github.com/luainkernel/lunatik#netfilter))
```
sudo make examples_install              # installs examples
examples/dnsdoctor/setup.sh             # sets up the environment

# test the setup, a response with IP 192.168.10.1 should be returned
dig lunatik.com

# run the Lua kernel script
sudo lunatik run examples/dnsdoctor/nf_dnsdoctor false

# test the setup, a response with IP 10.1.2.3 should be returned
dig lunatik.com

# cleanup
sudo lunatik unload
examples/dnsdoctor/cleanup.sh
```

## References

* [Scripting the Linux Routing Table with Lua](https://netdevconf.info/0x17/sessions/talk/scripting-the-linux-routing-table-with-lua.html)
* [Lua no Núcleo](https://www.youtube.com/watch?v=-ufBgy044HI) (Portuguese)
* [Linux Network Scripting with Lua](https://legacy.netdevconf.info/0x14/session.html?talk-linux-network-scripting-with-lua)
* [Scriptables Operating Systems with Lua](https://www.netbsd.org/~lneto/dls14.pdf)

## License

Lunatik is dual-licensed under [MIT](LICENSE-MIT) or [GPL-2.0-only](LICENSE-GPL).

[Lua](https://github.com/luainkernel/lua) submodule is licensed under MIT.
For more details, see its [Copyright Notice](https://github.com/luainkernel/lua/blob/lunatik/lua.h#L530-L556).

[Klibc](https://github.com/luainkernel/klibc) submodule is dual-licensed under BSD 3-Clause or GPL-2.0-only.
For more details, see its [LICENCE](https://github.com/luainkernel/klibc/blob/lunatik/usr/klibc/LICENSE) file.

