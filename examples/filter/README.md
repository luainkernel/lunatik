# filter

**filter** is a kernel extension composed by
a XDP/eBPF program to filter HTTPS sessions and
a Lua kernel script to filter [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) TLS extension.
This kernel extension drops any HTTPS request destinated to a
[blacklisted](sni.lua#L35) server.

## Usage

Usage requires `libbpf` and `bpftool` installed.

Come back to this repository, install and load the filter:

```sh
cd ${LUNATIK_DIR}/lunatik    # cf. above
sudo make btf_install        # needed to export the 'bpf_luaxdp_run' kfunc
sudo make examples_install   # installs examples
make ebpf                    # builds the XDP/eBPF program
sudo make ebpf_install       # installs the XDP/eBPF program
# Run the Lua kernel script, one runtime per CPU
sudo lunatik run --context=softirq --percpu examples/filter/sni
# Load the compiled XDP/eBPF program and attach to interface <ifname>
sudo bpftool prog load examples/filter/https.o /sys/fs/bpf/lunatik_filter type xdp
sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev <ifname>
```

For example, testing is easy thanks to [docker](https://www.docker.com).
Assuming docker is installed and running:

- in a terminal:
```sh
sudo bpftool prog load example/filter/https.o /sys/fs/bpf/lunatik_filter type xdp
sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev docker0
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

