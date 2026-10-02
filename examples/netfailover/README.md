# netfailover

**netfailover** reroutes in reaction to a link: when the
watched interface (`dummy0`) goes down, a backup route to 192.0.2.1 is installed
in table 200 with `netlink.rt`, and removed when the link comes back up; each
change is announced as a line of text, such as `dummy0 down: backup route installed`,
sent as the raw generic netlink body of command 1 to the one multicast group of the
`netfailover` family of a `netlink.channel`, and printed to `dmesg` as
`netfailover: dummy0 down: backup route installed`, the easiest place to watch it.
[control](control.lua) owns `notifier.netdevice`, whose
callback runs under RTNL, where a `netlink.rt` request is refused, so it only
records the link state in an `rcu.table`; [reactor](reactor.lua),
a spawned thread, polls that table and reprograms the route. They are two
runtimes because the notifier's runtime refuses the reactor's request: the
reactor would hold the runtime lock while it waits for RTNL, as the callback
holds RTNL waiting for the runtime lock.

## Usage

```
sudo make install                                  # installs Lunatik and the examples
sudo ip link add dummy0 type dummy && sudo ip link set dummy0 up
sudo lunatik run examples/netfailover/control       # records the link state
sudo lunatik spawn examples/netfailover/reactor     # reroutes on it
sudo ip link set dummy0 down                        # installs the backup route
ip route show table 200
192.0.2.1 dev lo proto static scope link
sudo ip link set dummy0 up                          # removes it
sudo lunatik stop examples/netfailover/reactor
sudo lunatik stop examples/netfailover/control
sudo ip link del dummy0
```

