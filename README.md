# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](lunatik.lua) (written in Lua =)) and a [command line tool](lunatik)
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
Lunatik 3.0  Copyright (C) 2023 ring-0 Ltda.
> return 42 -- execute this line in the kernel
42
```

### lunatik

```Shell
usage: lunatik [load|unload|reload|status] [run|stop <script>]
```

* `load`: load Lunatik kernel modules
* `unload`: unload Lunatik kernel modules
* `reload`: reload Lunatik kernel modules
* `status`: show what Lunatik kernel modules are currently loaded
* `run`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`
* `stop`: stop the runtime environment created to run the script `<script>`
* `default`: start a _REPL (Read–Eval–Print Loop)_

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

### socket

The `socket` library provides support for the kernel
[networking handling](https://elixir.bootlin.com/linux/latest/source/include/linux/net.h).
This library was inspired by
[Chengzhi Tan](https://github.com/tcz717)'s
[GSoC project](https://summerofcode.withgoogle.com/archive/2018/projects/5993341447569408).

#### `socket.new(family, type, protocol)`

_socket.new()_ creates a new `socket`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1).
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

#### `socket:close(sock)`, `sock:close()`

_socket.close()_ removes `sock`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1)
from the system.

#### `socket.send(sock, message, [addr [, port]])`, `sock:send(message, [addr [, port]])`

_socket.send()_ sends a string `message` through the socket `sock`.
If the `sock` address family is `af.INET`, then it expects the following arguments:
* `addr`: `integer` describing the destination IPv4 address.
* `port`: `integer` describing the destination IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the destination address.

#### `socket.receive(sock, length, [flags [, from]])`, `sock:receive(length, [flags [, from]])`

_socket.receive()_ receives a string with up to `length` bytes through the socket `sock`.
The available _message flags_ are defined by the
[socket.message](https://github.com/luainkernel/lunatik#socketmsg) table.
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

#### `socket.bind(sock, addr [, port])`, `sock:bind(addr [, port])`

_socket.bind()_ binds the socket `sock` to a given address.
If the `sock` address family is `af.INET`, then it expects the following arguments:
* `addr`: `integer` describing host IPv4 address.
* `port`: `integer` describing host IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing host address.

#### `socket.listen(sock [, backlog])`, `sock:listen([backlog])`

_socket.listen()_ moves the socket `sock` to listening state.
It returns a new socket
* `backlog`: pending connections queue size.
If omitted, it uses
[SOMAXCONN](https://elixir.bootlin.com/linux/latest/source/include/linux/socket.h#L296)
as default.

#### `socket.accept(sock [, flags])`, `sock:accept([flags])`

_socket.accept()_ accepts a connection on socket `sock`.
It returns a new `socket`
[userdata](https://www.lua.org/manual/5.4/manual.html#2.1).
The available _flags_ are present on the
[socket.sock](https://github.com/luainkernel/lunatik#socketsock) table.

#### `socket.connect(sock, addr [, port] [, flags])`, `sock:connect(addr [, port] [, flags])`

_socket.connect()_ connects the socket `sock` to the address `addr`.
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

#### `socket.getsockname(sock)`, `sock:getsockname()`

_socket.getsockname()_ get the address which the socket `sock` is bound.
If the `sock` address family is `af.INET`, then it returns the following:
* `addr`: `integer` describing the bounded IPv4 address.
* `port`: `integer` describing the bounded IPv4 port. 

Otherwise:
* `addr`: [packed string](https://www.lua.org/manual/5.4/manual.html#6.4.2) describing the bounded address.

#### `socket.getpeername(sock)`, `sock:getpeername()`

_socket.getpeername()_ get the address which the socket `sock` is connected.
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

## References

* [Scriptables Operating Systems with Lua](https://www.netbsd.org/~lneto/dls14.pdf)
* [Linux Network Scripting with Lua](https://legacy.netdevconf.info/0x14/session.html?talk-linux-network-scripting-with-lua)

