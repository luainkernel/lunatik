# linkflap

[linkflap](watch.lua) detects an interface that flaps: a
`notifier.netdevice` callback keeps each interface's UP and DOWN transitions of
the last 10 seconds, the initial namespace's only since a homonym elsewhere
would announce under the same name, and once one interface reaches 5 it
multicasts a flapping event, the interface name and the transition count as
generic netlink attributes, on the `linkflap` family of a `netlink.channel`.
[subscriber](subscriber.c) joins that family's multicast group
from userspace and prints each event. The callback runs holding RTNL, which a
multicast does not take, so one runtime does both. Registering the notifier
replays an `UP` for each interface that already exists, one transition each.

## Usage

```
sudo make install                                     # installs Lunatik and the examples
sudo lunatik run examples/linkflap/watch               # arms the notifier
cc -O2 examples/linkflap/subscriber.c -o linkflap-sub  # builds the subscriber
GRP=$(genl ctrl get name linkflap | grep -oiE 'ID-0x[0-9a-f]+' | sed 's/^ID-//i')
sudo ./linkflap-sub "$GRP" &                           # prints each event
sudo ip link add dummy0 type dummy
for i in 1 2 3; do sudo ip link set dummy0 up; sudo ip link set dummy0 down; done
linkflap: dummy0 flapping (5 transitions)
sudo ip link del dummy0
sudo lunatik stop examples/linkflap/watch
```

