# lldpd

[lldpd](daemon.lua) shows how to implement a simple LLDP transmitter in kernel space using Lunatik.
It periodically emits LLDP frames on a given interface using an AF_PACKET socket.

## Usage

```
sudo make examples_install                  # installs examples

# the LLDP daemon sends frames on a single Ethernet interface
# you may use an existing interface, or create a virtual one for testing

# create a veth pair (the example uses veth0 by default)
ip link add veth0 type veth peer name veth1
ip link set veth0 up
ip link set veth1 up

sudo lunatik spawn examples/lldpd/daemon    # runs lldpd

# verify LLDP frames are being transmitted
sudo tcpdump -i veth0 -e ether proto 0x88cc -vv
```

