# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](driver.lua) (written in Lua =)) and a [command line tool](bin/lunatik)
to load and run scripts and manage runtime environments from the user space;
a [C API](#lunatik-c-api) to load and run scripts and manage runtime environments from the kernel;
and [Lua APIs](#lunatik-lua-apis) for binding kernel facilities to Lua scripts.

> Note: Lunatik supports Linux Kernel versions 5.x and 6.x

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

## Setup

Install dependencies (here for Debian/Ubuntu, to be adapted to one's distribution):

```sh
sudo apt install git build-essential lua5.4 dwarves clang llvm libelf-dev linux-headers-$(uname -r) linux-tools-common linux-tools-$(uname -r) pkg-config libpcap-dev m4
```

Install dependencies (here for Arch Linux):

```sh
sudo pacman -S git lua clang llvm m4 libpcap pkg-config build2 linux-tools linux-headers
```

Compile and install `lunatik`:

```sh
LUNATIK_DIR=~/lunatik  # to be adapted
mkdir "${LUNATIK_DIR}" ; cd "${LUNATIK_DIR}"
git clone --depth 1 --recurse-submodules https://github.com/luainkernel/lunatik.git
cd lunatik
make
sudo make install
```

Once done, the `debian_kernel_postinst_lunatik.sh` script from tools/ may be copied into
`/etc/kernel/postinst.d/`: this ensures `lunatik` (and also the `xdp` needed libs) will get
compiled on kernel upgrade.

### OpenWRT

Install Lunatik from our [package feed](https://github.com/luainkernel/openwrt_feed/tree/openwrt-23.05).

## Usage

```
sudo lunatik # execute Lunatik REPL
Lunatik 3.7  Copyright (C) 2023-2025 ring-0 Ltda.
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

Lunatik 3.7 is based on
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

## Lunatik Lua APIs

Lua APIs are documented thanks to [LDoc](https://stevedonovan.github.io/ldoc/). This documentation can be read here: https://luainkernel.github.io/lunatik/, and in the source files.

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

Compile and install `libbpf`, `libxdp` and `xdp-loader`:

```sh
mkdir -p "${LUNATIK_DIR}" ; cd "${LUNATIK_DIR}"  # LUNATIK_DIR must be set to the same value as above (Setup section)
git clone --depth 1 --recurse-submodules https://github.com/xdp-project/xdp-tools.git
cd xdp-tools/lib/libbpf/src
make
sudo DESTDIR=/ make install
cd ../../../
make libxdp
cd xdp-loader
make
sudo make install
```

Come back to this repository, install and load the filter:

```sh
cd ${LUNATIK_DIR}/lunatik                    # cf. above
sudo make btf_install                        # needed to export the 'bpf_luaxdp_run' kfunc
sudo make examples_install                   # installs examples
make ebpf                                    # builds the XDP/eBPF program
sudo make ebpf_install                       # installs the XDP/eBPF program
sudo lunatik run examples/filter/sni false   # runs the Lua kernel script
sudo xdp-loader load -m skb <ifname> https.o # loads the XDP/eBPF program
```

For example, testing is easy thanks to [docker](https://www.docker.com).
Assuming docker is installed and running:

- in a terminal:
```sh
sudo xdp-loader load -m skb docker0 https.o
sudo journalctl -ft kernel
```
- in another one:
```sh
docker run --rm -it alpine/curl https://ebpf.io
```

The system logs (in the first terminal) should display `filter_sni: ebpf.io DROP`, and the
`docker run…` should return `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to ebpf.io:443`.

### filter in MoonScript

[This other sni filter](https://github.com/luainkernel/snihook) uses netfilter api.

### dnsblock

[dnsblock](examples/dnsblock) is a kernel script that uses the lunatik xtable library to filter DNS packets.
This script drops any outbound DNS packet with question matching the blacklist provided by the user. By default, it will block DNS resolutions for the domains `github.com` and `gitlab.com`.

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

### gesture

[gesture](examples/gesture.lua)
is a kernel script that implements a HID driver for QEMU USB Mouse (0627:0001).
It supports gestures: swiping up locks the mouse, and swiping down unlocks it.

#### Usage

1. You need to change the display protocal into `VNC` and enable USB mouse device in QEMU, the following configuration can help you disable PS2 mouse & enable USB mouse:

```
<features>
	<!-- ... -->
	<ps2 state="off"/>
	<!-- ... -->
</features>
```

2. run the gesture script:

```
sudo make examples_install 			# installs examples
sudo lunatik run examples/gesture false 	# runs gesture
# In QEMU window:
# Drag up to lock the mouse
# Drag down to unlock the mouse
```

### xiaomi

[xiaomi](examples/xiaomi.lua)
is a kernel script that ports the Xiaomi Silent Mouse driver to Lua using `luahid`.
It fixes the report descriptor for the device (`0x2717`:`0x5014`).

#### Usage

```
sudo make examples_install 		# installs examples
sudo lunatik run examples/xiaomi false 	# runs xiaomi driver
```

Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.

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

