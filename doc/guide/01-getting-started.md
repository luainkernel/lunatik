# Getting started


Install dependencies (here for Debian/Ubuntu, to be adapted to one's distribution):

```sh
sudo apt install git build-essential lua5.5 dwarves clang llvm libelf-dev linux-headers-$(uname -r) linux-tools-common linux-tools-$(uname -r) pkg-config libpcap-dev m4
```

Install dependencies (here for Arch Linux):

```sh
sudo pacman -S git lua clang llvm m4 libpcap pkg-config base-devel pahole libelf linux-tools linux-headers
```

The command line tool runs under `/usr/bin/lua5.5`, and the build calls `lua5.5`. Ubuntu packages
Lua 5.5 from 26.04 and Debian from testing. Where the distribution does not carry it yet, build the
interpreter from source:

```sh
curl -sSLO https://www.lua.org/ftp/lua-5.5.1.tar.gz
tar xf lua-5.5.1.tar.gz && make -C lua-5.5.1
sudo install -m 0755 lua-5.5.1/src/lua /usr/bin/lua5.5
```

The `lua-readline` package is optional. When installed, the REPL gains line editing and command history:

```sh
sudo apt install lua-readline  # Debian/Ubuntu
```

Compile and install Lunatik:

```sh
LUNATIK_DIR=~/lunatik  # to be adapted
mkdir "${LUNATIK_DIR}" ; cd "${LUNATIK_DIR}"
git clone --depth 1 --recurse-submodules https://github.com/luainkernel/lunatik.git
cd lunatik
sudo make btf_install
make
sudo make install
```

`sudo make btf_install` copies the running kernel's BTF, `/sys/kernel/btf/vmlinux`, into the
headers the modules build against. Without it the modules are built with no BTF of their own:
`xdp` and `tc`, and `sched` on a kernel with sched_ext, still load, but log `missing module BTF` in
the kernel log and leave their kfunc unregistered, so an eBPF program that calls one, such as
`bpf_luaxdp_run`, fails to load.

## Check the install

```sh
sudo lunatik load      # loads the modules
sudo lunatik status    # one line per module: <module> is loaded
sudo lunatik -V        # the version of the loaded Lunatik
```

## After a kernel upgrade

The modules are installed for one kernel release, under `/lib/modules/$(uname -r)`, so on a new
kernel `sudo lunatik` fails with `lunatik: couldn't create /dev/lunatik`. Install the new kernel's
headers and tools, then rebuild:

```sh
sudo apt install linux-headers-$(uname -r) linux-tools-$(uname -r)  # Debian/Ubuntu
make clean
sudo make btf_install
make
sudo make install
```

On Debian and Ubuntu, a kernel hook can do this on every upgrade: [tools/Readme.md](../../tools/Readme.md)
installs `tools/debian_kernel_postinst_lunatik.sh` as `/etc/kernel/postinst.d/zz-update-lunatik`.
The hook builds its own clone of master under `/opt/lunatik`, not your checkout. It downloads the
kernel sources to build `resolve_btfids` and `bpftool`, and replaces `/usr/sbin/bpftool` with the one
it built; it builds `xdp-loader` from xdp-tools under `/opt/xdp-tools`. A failure in it fails the
kernel package's configuration.

## Uninstall

```sh
sudo lunatik unload
sudo make uninstall
```

Run `sudo make ebpf_uninstall` too if you installed the eBPF programs with `sudo make ebpf_install`,
and remove `/etc/kernel/postinst.d/zz-update-lunatik` if you installed the hook.

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

