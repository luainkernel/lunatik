# sniclassify

**sniclassify** is a kernel extension composed by
a TC/eBPF classifier program attached on egress,
a Lua kernel script to classify [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) traffic.
This kernel extension extracts server name and assigns traffic
classes according to a Lua [policy table](sni.lua#L26).

Install the classifier:

```sh
sudo make btf_install         # needed to export the 'bpf_luatc_run' kfunc
sudo make examples_install    # installs examples
make ebpf                     # builds the TC/eBPF program
sudo make ebpf_install        # installs the TC/eBPF program
```

Run the classifier and set up the HTB classes on an interface:
```sh
sudo ./examples/sniclassify/setup.sh eth0
```

Tear it down with:
```sh
sudo ./examples/sniclassify/cleanup.sh eth0
```

The classifier inspects outbound TLS ClientHello packets, extracts the SNI
field, and assigns a traffic class according to the Lua policy table.

Verify and test:
```
sudo tc filter show dev eth0
sudo journalctl -ft kernel
```

