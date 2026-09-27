# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
Scripts run inside the kernel and reach its facilities through Lua modules: character devices,
Netfilter, XDP and TC hooks, kprobes, fsnotify, sched_ext, eBPF maps, sockets, netlink, crypto,
kernel threads and more. A command line tool loads and manages them from user space, and a
[C API](doc/capi.md) lets kernel modules do the same.

Lunatik supports Linux 6.6 and later. Its documentation is at
[luainkernel.github.io/lunatik](https://luainkernel.github.io/lunatik/). Join us on
[Matrix](https://matrix.to/#/#lunatik:matrix.org).


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
local stat   = require("linux.stat")

local driver = {name = "passwd", mode = stat.IRUGO}

function driver:read() -- read(2) callback
	-- generate random ASCII printable characters
	return string.char(linux.random(32, 126))
end

-- creates a new character device
device.new(driver)
```

## Get started

```sh
git clone --depth 1 --recurse-submodules https://github.com/luainkernel/lunatik.git
cd lunatik && make && sudo make install
sudo lunatik    # a REPL whose lines run in the kernel
```

Dependencies, OpenWRT and the first steps are in [Getting started](doc/guide/01-getting-started.md).

## Documentation

* [Getting started](doc/guide/01-getting-started.md): install, build, first script
* [Running scripts](doc/guide/02-running-scripts.md): the `lunatik` command, execution contexts, `lunatic`
* [Per-CPU scripts](doc/guide/03-percpu.md): one runtime per CPU, and where state belongs
* [Lua in the kernel](doc/guide/04-lua.md): what differs from userspace Lua
* [Examples](doc/guide/05-examples.md): device drivers, packet filters, probes, filesystem guards
* [Lua API reference](https://luainkernel.github.io/lunatik/#api-reference) and [C API](doc/capi.md)
* [Development](doc/guide/06-development.md) and [Resources](doc/guide/07-resources.md): tests, contributing, talks and papers

## License

Lunatik is dual-licensed under [MIT](LICENSE-MIT) or [GPL-2.0-only](LICENSE-GPL).

[Lua](https://github.com/luainkernel/lua) submodule is licensed under MIT.
For more details, see its [Copyright Notice](https://github.com/luainkernel/lua/blob/lunatik/lua.h#L530-L556).

[Klibc](https://github.com/luainkernel/klibc) submodule is dual-licensed under BSD 3-Clause or GPL-2.0-only.
For more details, see its [LICENCE](https://github.com/luainkernel/klibc/blob/lunatik/usr/klibc/LICENSE) file.

