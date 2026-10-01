# lldpd

[lldpd](daemon.lua) sends and receives LLDP on one AF_PACKET socket. It remembers neighbors by
`chassis@port` (port, system name, TTL) and forgets them when the advertised TTL elapses, or at once
when a frame carries TTL 0. The remaining TTL in seconds is an `rcu.table` on `lunatik._ENV.lldpd`.
A receive timeout of one second bounds `lunatik stop`. A neighbor's remaining TTL is the advertised TTL minus the seconds since its last frame.
[report](report.lua) reads that table from the REPL.

The interface is `config.interface` in [daemon.lua](daemon.lua), `veth0` by default, and a frame goes out
every 30 seconds (`tx_interval_ms`).

## Usage

```
sudo make install                          # installs Lunatik and the examples

# the LLDP daemon sends and receives on a single Ethernet interface
# you may use an existing interface, or create a virtual one for testing

# create a veth pair (the example uses veth0 by default)
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth0 up
sudo ip link set veth1 up

sudo lunatik spawn examples/lldpd/daemon    # runs lldpd

# verify LLDP frames are being transmitted and received
sudo tcpdump -i veth0 -e ether proto 0x88cc -vv

# view remaining TTL per neighbor from another terminal
sudo lunatik                               # opens the kernel REPL
> n = require("examples.lldpd.report")
> n.report()

sudo lunatik stop examples/lldpd/daemon     # stops lldpd
sudo ip link del veth0
```
