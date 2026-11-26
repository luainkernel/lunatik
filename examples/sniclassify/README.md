# sniclassify

**sniclassify** is a kernel extension composed by
a TC program written in Lua, [sni.bpf.lua](sni.bpf.lua), attached on egress, and
a Lua kernel script to classify [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) traffic.
This kernel extension extracts server name and assigns traffic
classes according to a Lua [policy table](sni.lua#L17): `netflix.com` and its subdomains go to class
1:30 (20 mbit guaranteed, prio 3), `zoom.com` and its subdomains to 1:10 (50 mbit guaranteed, prio 1),
and everything else to the HTB default, 1:20 (30 mbit guaranteed, prio 2); each class borrows up to the
100 mbit ceiling when the others leave it room.

Needs a kernel with BTF (`/sys/kernel/btf/vmlinux`), and libbpf 1.3.0 or later to attach the TC program.
`setup.sh` puts a 100 mbit HTB at the root of the interface in place of its default qdisc, which caps
everything the host sends there until `cleanup.sh` deletes it, so prefer a test interface, a veth, to
your uplink. Only IPv4 ClientHellos are classified.

Install the classifier:

```sh
sudo make btf_install         # needed to export the 'bpf_luatc_run' kfunc, before the build
make clean && make            # builds the modules again, now with their BTF
sudo make install             # installs Lunatik and the examples, and compiles the TC program
```

Set up the HTB classes on an interface, then run the Lua script, one runtime per CPU, and attach the TC
program to the interface:
```sh
sudo ./examples/sniclassify/setup.sh eth0
sudo lunatik run --context=softirq --percpu --dev=eth0 examples/sniclassify/sni
```

Tear it down with:
```sh
sudo ./examples/sniclassify/cleanup.sh eth0
```

The classifier inspects outbound TLS ClientHello packets, extracts the SNI
field, and assigns a traffic class according to the Lua policy table. The TC program keeps the class
of each flow in a map, so the packets after a flow's ClientHello take it without reaching the script;
once the map holds 65536 flows, a new one takes the place of the one seen least recently.

Verify and test:
```
sudo tc -s class show dev eth0            # counts what each class sent
sudo journalctl -ft kernel                # follows the kernel log
curl -so /dev/null https://zoom.com       # in another terminal, logs sniclassify: zoom.com 65552
```

