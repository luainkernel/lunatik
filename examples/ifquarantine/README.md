# ifquarantine

**ifquarantine** composes two notifier chains to build
an interface-level default-deny policy: every new network interface
(NETDEV_REGISTER) is automatically added to a shared RCU set whose contents
a netfilter hook uses to decide the verdict on each packet. An interface is
released from quarantine by writing `allow=<name>` to `/dev/ifquarantine`;
re-denied with `deny=<name>`; inspected with `cat /dev/ifquarantine`.

The control runtime (process context) owns `notifier.netdevice` and the
device; it runs the netfilter hook as a softirq percpu script, one runtime
per CPU sharing the hook, and hands each the quarantine set via `rcu.table`
through `percpu:resume()`. Illustrates cross-subsystem composition between
two notifier chains of different execution contexts.

## Usage

```
sudo make install                                 # installs Lunatik and the examples
sudo lunatik run examples/ifquarantine/control     # starts control+filter
sudo cat /dev/ifquarantine                         # lists known interfaces and verdict
sudo sh -c "echo 'deny=eth0'  > /dev/ifquarantine" # quarantine eth0
sudo sh -c "echo 'allow=eth0' > /dev/ifquarantine" # lift the quarantine
sudo lunatik stop examples/ifquarantine/control    # stops both scripts
```

The interfaces that already exist are recorded and allowed, not quarantined:
`register_netdevice_notifier` synchronously replays `NETDEV_REGISTER` (and
`NETDEV_UP`) for each netdev every namespace already has when the notifier
block is registered, inside `notifier.netdevice`, so the script records what
arrives before that call returns, and a policy that denied those would take the
machine off the network, `lo` and the uplink included. They are listed by `cat
/dev/ifquarantine` and can be quarantined with `deny=<name>`. The callback is
handed each device's namespace with its name, and the script keeps the devices
of its own, which `linux.netns()` names: a container's `lo` is reported too,
and its name would resolve onto the host's through `linux.ifindex`.

