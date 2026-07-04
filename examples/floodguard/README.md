# floodguard — adaptive in-kernel blackholing

Detects flooding sources and blackholes them in the dataplane, in Lua, in
softirq, and streams each mitigation to userspace over a netlink channel. No
userspace agent sits in the packet path.

A `PRE_ROUTING` netfilter hook counts packets per source address in an
`rcu.table`; once a source crosses `THRESHOLD` packets it is dropped (`DROP`) and
a `blackholed <ip>` event is multicast on the `floodguard` netlink channel. This
is a minimal illustration: counts are not aged, so a source stays blackholed for
the life of the runtime.

## Run

```sh
sudo lunatik run examples/floodguard/filter softirq   # softirq: hook + channel

sudo dmesg -w | grep floodguard &                     # watch mitigations
```

The channel is a generic netlink family named `floodguard` with one multicast
group; a userspace dashboard can subscribe to it and print the live feed —
`tests/netlink/channel_subscriber.c` is a minimal subscriber to build on.

## Demo

Drive traffic from a distinct source (e.g. a network namespace) past the
threshold and watch it get blackholed:

```sh
sudo ip netns add attacker
sudo ip link add veth-h type veth peer name veth-a
sudo ip link set veth-a netns attacker
sudo ip addr add 10.99.0.1/24 dev veth-h && sudo ip link set veth-h up
sudo ip netns exec attacker ip addr add 10.99.0.2/24 dev veth-a
sudo ip netns exec attacker ip link set veth-a up

sudo ip netns exec attacker ping -c 150 -i 0.01 10.99.0.1   # ~100 get through, rest dropped
```

## Stop

```sh
sudo lunatik stop examples/floodguard/filter
sudo ip netns del attacker && sudo ip link del veth-h
```

