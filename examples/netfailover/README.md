# netfailover

**netfailover** reroutes in reaction to a link: when the
watched interface (`dummy0`) goes down, a backup route to 192.0.2.1 is installed
in table 200 with `netlink.rt`, and removed when the link comes back up; each
change is announced as a line of text, such as `dummy0 down: backup route installed`,
sent as the raw generic netlink body of command 1 to the one multicast group of the
`netfailover` family of a `netlink.channel`, and printed to `dmesg` as
`netfailover: dummy0 down: backup route installed`, the easiest place to watch it.
[control](control.lua) registers `notifier.netdevice`, whose callback reprograms
the route and announces it on each `DOWN` and `UP` of the watched link; the
replayed `UP` of a link already up at load changes nothing.

## Usage

```
sudo make install                                  # installs Lunatik and the examples
sudo ip link add dummy0 type dummy && sudo ip link set dummy0 up
sudo lunatik run examples/netfailover/control       # reroutes on the link state
sudo ip link set dummy0 down                        # installs the backup route
ip route show table 200
192.0.2.1 dev lo proto static scope link
sudo ip link set dummy0 up                          # removes it
sudo lunatik stop examples/netfailover/control
sudo ip link del dummy0
```

