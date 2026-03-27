# Lunatik

Lunatik is a framework for scripting the Linux kernel with [Lua](https://www.lua.org/).
It is composed by the Lua interpreter modified to run in the kernel;
a [device driver](driver.lua) (written in Lua =)) and a [command line tool](bin/lunatik)
to load and run scripts and manage runtime environments from the user space;
a [C API](doc/capi.md) to load and run scripts and manage runtime environments from the kernel;
and [Lua APIs](#lunatik-lua-apis) for binding kernel facilities to Lua scripts.

> Note: Lunatik supports Linux Kernel versions 5.x and 6.x

Feel free to join us on [Matrix](https://matrix.to/#/#lunatik:matrix.org).

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

The `lua-readline` package is optional. When installed, the REPL gains line editing and command history:

```sh
sudo apt install lua-readline  # Debian/Ubuntu
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
Lunatik 4.2  Copyright (C) 2023-2026 Ring Zero Desenvolvimento de Software LTDA.
> return 42 -- execute this line in the kernel
42
```

### lunatik

```Shell
usage: lunatik [load|unload|reload|status|test|list] [run|spawn|stop <script>]
```

* `load`: load Lunatik kernel modules
* `unload`: unload Lunatik kernel modules
* `reload`: reload Lunatik kernel modules
* `status`: show which Lunatik kernel modules are currently loaded
* `test [suite]`: run installed test suites (see [Testing](#testing))
* `list`: show which

## Contributing

Contributions are welcome! You can help by reporting bugs, suggesting new features, or submitting Pull Requests. For major changes, please open an issue first to discuss what you would like to change. Please ensure that your code follows the existing style and includes appropriate documentation and tests.

## License

This project is licensed under the [MIT License](LICENSE).