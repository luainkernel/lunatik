# Getting started


Install dependencies (here for Debian/Ubuntu, to be adapted to one's distribution):

```sh
sudo apt install git build-essential lua5.5 dwarves clang llvm libelf-dev linux-headers-$(uname -r) linux-tools-common linux-tools-$(uname -r) pkg-config libpcap-dev m4
```

Install dependencies (here for Arch Linux):

```sh
sudo pacman -S git lua clang llvm m4 libpcap pkg-config build2 linux-tools linux-headers
```

Ubuntu packages Lua 5.5 from 26.04 and Debian from testing. Where the distribution does not carry
it yet, build the interpreter from source:

```sh
curl -sSLO https://www.lua.org/ftp/lua-5.5.1.tar.gz
tar xf lua-5.5.1.tar.gz && make -C lua-5.5.1
sudo install -m 0755 lua-5.5.1/src/lua /usr/bin/lua5.5
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

## OpenWRT

Install Lunatik from our [package feed](https://github.com/luainkernel/openwrt_feed).

## First steps

```
sudo lunatik # execute Lunatik REPL
Lunatik 4.4  Copyright (C) 2023-2026 Ring Zero Desenvolvimento de Software LTDA.
> return 42 -- execute this line in the kernel
42
```


Next, [run a script](02-running-scripts.md) or browse the [examples](05-examples.md).

