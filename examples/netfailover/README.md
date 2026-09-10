# netfailover — reactive policy routing from the kernel

Reprograms routing in reaction to a link going down, entirely in-kernel, in Lua,
hot-loaded. No userspace routing daemon, no recompile.

When the watched interface (`dummy0` by default) goes **down**, a backup route is
installed in table `200`; when it comes back **up**, the route is removed. The
decision and the rtnetlink write both happen inside the kernel.

## Why two runtimes

A netdevice notifier callback runs holding `rtnl_lock`. Issuing rtnetlink from it
would re-enter `rtnl_lock` and **self-deadlock**, so the work is split:

- `control.lua` (process runtime) registers the `notifier.netdevice` callback,
  which only records the link state into a shared `rcu.table`. Fast, lock-safe.
- `reactor.lua` (spawned kthread, sleepable) polls that state and reprograms
  routing with `netlink.rt.route` — `rtnl_lock` is not held here — and broadcasts each
  action on a `netlink.channel` for a userspace dashboard.

The two live in separate runtimes on purpose: sharing one would let the reactor
hold the runtime lock while waiting on `rtnl_lock` as the notifier holds
`rtnl_lock` waiting on the runtime lock — a classic ABBA deadlock.

## Run

```sh
sudo ip link add dummy0 type dummy && sudo ip link set dummy0 up

sudo lunatik run   examples/netfailover/control
sudo lunatik spawn examples/netfailover/reactor

# watch the reactions
sudo dmesg -w | grep netfailover &

sudo ip link set dummy0 down   # -> backup route installed in table 200
ip route show table 200
sudo ip link set dummy0 up     # -> backup route removed
```

## Stop

```sh
sudo lunatik stop examples/netfailover/reactor
sudo lunatik stop examples/netfailover/control
sudo ip link del dummy0
```

