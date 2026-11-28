# filter

**filter** is a kernel extension composed by
an XDP program written in Lua, [sni.bpf.lua](sni.bpf.lua), to filter HTTPS sessions and
a Lua kernel script to filter [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) TLS extension.
This kernel extension drops any HTTPS request destinated to a
[blacklisted](sni.lua#L16) server, `ebpf.io` by default, matched on the exact server name.
Only IPv4 TLS ClientHellos to port 443 are recognized,
and only in the frames `<ifname>` receives: attached to an uplink, it does not see the host's own requests.

## Usage

Requires a kernel with BTF (`/sys/kernel/btf/vmlinux`).

From the root of the Lunatik checkout (see [getting started](../../doc/guide/01-getting-started.md)):

```sh
sudo make btf_install        # needed to export the 'bpf_luaxdp_run' kfunc, before the build
make clean && make           # builds the modules again, now with their BTF
sudo make install            # installs Lunatik and the examples, and compiles the XDP program
# Run the Lua kernel script, one runtime per CPU, and attach the XDP program to interface <ifname>
sudo lunatik run --context=softirq --percpu --dev=<ifname> examples/filter/sni
```

Tear it down with:

```sh
sudo lunatik stop examples/filter/sni
```

For example, testing is easy thanks to [docker](https://www.docker.com).
Assuming docker is installed and running, follow the steps above with `docker0` as `<ifname>`:

```sh
sudo lunatik run --context=softirq --percpu --dev=docker0 examples/filter/sni
```

Then:

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

