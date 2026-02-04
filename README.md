# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](driver.lua) (written in Lua =)) and a [command line tool](bin/lunatik)
to load and run scripts and manage runtime environments from the user space;
a [C API](doc/capi.md) to load and run scripts and manage runtime environments from the kernel;
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

local s = linux.stat
local driver = {name = "passwd", mode = s.IRUGO}

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
Lunatik 4.1  Copyright (C) 2023-2026 Ring Zero Desenvolvimento de Software LTDA.
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

Lunatik 4.1 is based on
[Lua 5.5 adapted](https://github.com/luainkernel/lua)
to run in the kernel.

### Floating-point numbers

Lunatik **does not** support floating-point arithmetic,
thus it **does not** support `__div` nor `__pow`
[metamethods](https://www.lua.org/manual/5.5/manual.html#2.4)
and the type _number_ has only the subtype _integer_.

### Lua API

Lunatik **does not** support both [io](https://www.lua.org/manual/5.5/manual.html#6.8) and
[os](https://www.lua.org/manual/5.5/manual.html#6.9) libraries,
and the given identifiers from the following libraries:
* [debug.debug](https://www.lua.org/manual/5.5/manual.html#pdf-debug.debug),
[math.acos](https://www.lua.org/manual/5.5/manual.html#pdf-math.acos),
[math.asin](https://www.lua.org/manual/5.5/manual.html#pdf-math.asin),
[math.atan](https://www.lua.org/manual/5.5/manual.html#pdf-math.atan),
[math.ceil](https://www.lua.org/manual/5.5/manual.html#pdf-math.ceil),
[math.cos](https://www.lua.org/manual/5.5/manual.html#pdf-math.cos),
[math.deg](https://www.lua.org/manual/5.5/manual.html#pdf-math.deg),
[math.exp](https://www.lua.org/manual/5.5/manual.html#pdf-math.exp),
[math.floor](https://www.lua.org/manual/5.5/manual.html#pdf-math.floor),
[math.fmod](https://www.lua.org/manual/5.5/manual.html#pdf-math.fmod),
[math.frexp](https://www.lua.org/manual/5.5/manual.html#pdf-math.frexp),
[math.huge](https://www.lua.org/manual/5.5/manual.html#pdf-math.huge).
[math.ldexp](https://www.lua.org/manual/5.5/manual.html#pdf-math.ldexp),
[math.log](https://www.lua.org/manual/5.5/manual.html#pdf-math.log),
[math.modf](https://www.lua.org/manual/5.5/manual.html#pdf-math.modf),
[math.pi](https://www.lua.org/manual/5.5/manual.html#pdf-math.pi),
[math.rad](https://www.lua.org/manual/5.5/manual.html#pdf-math.rad),
[math.random](https://www.lua.org/manual/5.5/manual.html#pdf-math.random),
[math.randomseed](https://www.lua.org/manual/5.5/manual.html#pdf-math.randomseed),
[math.sin](https://www.lua.org/manual/5.5/manual.html#pdf-math.sin),
[math.sqrt](https://www.lua.org/manual/5.5/manual.html#pdf-math.sqrt),
[math.tan](https://www.lua.org/manual/5.5/manual.html#pdf-math.tan),
[math.type](https://www.lua.org/manual/5.5/manual.html#pdf-math.type),
[package.cpath](https://www.lua.org/manual/5.5/manual.html#pdf-package.cpath).

Lunatik **modifies** the following identifiers:
* [\_VERSION](https://www.lua.org/manual/5.5/manual.html#pdf-_VERSION): is defined as `"Lua 5.5-kernel"`.
* [collectgarbage("count")](https://www.lua.org/manual/5.5/manual.html#pdf-collectgarbage): returns the total memory in use by Lua in **bytes**, instead of _Kbytes_.
* [package.path](https://www.lua.org/manual/5.5/manual.html#pdf-package.path): is defined as `"/lib/modules/lua/?.lua;/lib/modules/lua/?/init.lua"`.
* [require](https://www.lua.org/manual/5.5/manual.html#pdf-require): only supports built-in or already linked C modules, that is, Lunatik **cannot** load kernel modules dynamically.

### C API

Lunatik **does not** support
[luaL\_Stream](https://www.lua.org/manual/5.5/manual.html#luaL_Stream),
[luaL\_execresult](https://www.lua.org/manual/5.5/manual.html#luaL_execresult),
[luaL\_fileresult](https://www.lua.org/manual/5.5/manual.html#luaL_fileresult),
[luaopen\_io](https://www.lua.org/manual/5.5/manual.html#pdf-luaopen_io) and
[luaopen\_os](https://www.lua.org/manual/5.5/manual.html#pdf-luaopen_os).

Lunatik **modifies** [luaL\_openlibs](https://www.lua.org/manual/5.5/manual.html#luaL_openlibs) to remove [luaopen\_io](https://www.lua.org/manual/5.5/manual.html#pdf-luaopen_io) and [luaopen\_os](https://www.lua.org/manual/5.5/manual.html#pdf-luaopen_os).

## Lunatik Lua APIs

Lua APIs are documented thanks to [LDoc](https://stevedonovan.github.io/ldoc/). This documentation can be read here: https://luainkernel.github.io/lunatik/, and in the source files.

## Lunatik C API

See [this](doc/capi.md) document.

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
It supports gestures: swiping right locks the mouse, and swiping left unlocks it.

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
# Drag right to lock the mouse
# Drag left to unlock the mouse
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

### lldpd

[lldpd](examples/lldpd.lua) shows how to implement a simple LLDP transmitter in kernel space using Lunatik.
It periodically emits LLDP frames on a given interface using an AF_PACKET socket.

#### Usage

```
sudo make examples_install                  # installs examples

# the LLDP daemon sends frames on a single Ethernet interface
# you may use an existing interface, or create a virtual one for testing

# create a veth pair (the example uses veth0 by default)
ip link add veth0 type veth peer name veth1
ip link set veth0 up
ip link set veth1 up

sudo lunatik spawn examples/lldpd           # runs lldpd

# verify LLDP frames are being transmitted
sudo tcpdump -i veth0 -e ether proto 0x88cc -vv
```

### cpuexporter

[cpuexporter](examples/cpuexporter.lua) will gather CPU usage statistics and expose using [OpenMetrics text format](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md#text-format) at a UNIX socket file.

#### Usage

```shell
sudo make examples_install         	# installs examples
sudo lunatik spawn examples/cpuexporter # runs cpuexporter
sudo socat - UNIX-CONNECT:/tmp/cpuexporter.sock <<<""
# TYPE cpu_usage_system gauge
cpu_usage_system{cpu="cpu1"} 0.0000000000000000 1764094519529162
cpu_usage_system{cpu="cpu0"} 0.0000000000000000 1764094519529162
# TYPE cpu_usage_idle gauge
cpu_usage_idle{cpu="cpu1"} 100.0000000000000000 1764094519529162
cpu_usage_idle{cpu="cpu0"} 100.0000000000000000 1764094519529162
...
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

