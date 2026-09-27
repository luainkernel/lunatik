# filter

**filter** is a kernel extension composed by
a XDP/eBPF program to filter HTTPS sessions and
a Lua kernel script to filter [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) TLS extension.
This kernel extension drops any HTTPS request destinated to a
[blacklisted](sni.lua#L16) server, `ebpf.io` by default, matched on the exact server name.
The XDP program reads every frame as IPv4, so only IPv4 TLS ClientHellos to port 443 are recognized,
and only in the frames `<ifname>` receives: attached to an uplink, it does not see the host's own requests.

## Usage

Requires clang, the libbpf headers, `bpftool` and a kernel with BTF (`/sys/kernel/btf/vmlinux`).

From the root of the Lunatik checkout (see [getting started](../../doc/guide/01-getting-started.md)):

```sh
sudo make btf_install        # needed to export the 'bpf_luaxdp_run' kfunc, before the build
make clean && make           # builds the modules again, now with their BTF
sudo make install            # installs Lunatik and the examples
make ebpf                    # builds the XDP/eBPF program, which bpftool loads from the checkout
# Run the Lua kernel script, one runtime per CPU
sudo lunatik run --context=softirq --percpu examples/filter/sni
# Load the compiled XDP/eBPF program and attach to interface <ifname>
sudo bpftool prog load examples/filter/https.o /sys/fs/bpf/lunatik_filter type xdp
sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev <ifname>
```

Tear it down with:

```sh
sudo bpftool net detach xdp dev <ifname>
sudo rm /sys/fs/bpf/lunatik_filter
sudo lunatik stop examples/filter/sni
```

For example, testing is easy thanks to [docker](https://www.docker.com).
Assuming docker is installed and running, follow the steps above with `docker0` as `<ifname>`, then:

- in a terminal:
```sh
sudo journalctl -ft kernel
```
- in another one:
```sh
docker run --rm -it alpine/curl https://ebpf.io
```

The system logs (in the first terminal) should display `filter_sni: ebpf.io DROP`, and the
`docker run…` should return `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to ebpf.io:443`.

## filter in MoonScript

[This other sni filter](https://github.com/luainkernel/snihook) uses netfilter api.

