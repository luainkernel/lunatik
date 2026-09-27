# Examples

## spyglass

[spyglass](../../examples/spyglass)
is a kernel script that implements a _keylogger_ inspired by the
[spy](https://github.com/jarun/spy) kernel module.
This kernel script logs the _keysym_ of the pressed keys in a device (`/dev/spyglass`).
If the _keysym_ is a printable character, `spyglass` logs the _keysym_ itself;
otherwise, it logs a mnemonic of the ASCII code, (e.g., `<del>` stands for `127`).

The keyboard notifier fires in hardirq context, whereas the device requires
process context; spyglass splits across two runtimes
([`device.lua`](../../examples/spyglass/device.lua) in process and
[`notifier.lua`](../../examples/spyglass/notifier.lua) in hardirq) sharing captured
chars via a [`fifo`](../../lib/luafifo.c).

### Usage

```
sudo make examples_install                 # installs examples
sudo lunatik run examples/spyglass/device  # runs spyglass
sudo tail -f /dev/spyglass                 # prints the key log
```

## keylocker

[keylocker](../../examples/keylocker/notifier.lua)
is a kernel script that implements
[Konami Code](https://en.wikipedia.org/wiki/Konami_Code)
for locking and unlocking the console keyboard.
When the user types `↑ ↑ ↓ ↓ ← → ← → LCTRL LALT`,
the keyboard will be _locked_; that is, the system will stop processing any key pressed
until the user types the same key sequence again.

The keyboard notifier fires in hardirq context, so keylocker must run in a
`hardirq` runtime (passed as the third argument to `lunatik run`).

### Usage

```
sudo make examples_install                         # installs examples
sudo lunatik run examples/keylocker/notifier hardirq # runs keylocker
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>     # locks keyboard
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>     # unlocks keyboard
```

## tap

[tap](../../examples/tap/device.lua)
is a kernel script that implements a _sniffer_ using `AF_PACKET` socket.
It prints destination and source MAC addresses followed by Ethernet type and the frame size.

### Usage

```
sudo make examples_install    # installs examples
sudo lunatik run examples/tap/device # runs tap
cat /dev/tap
```

## shared

[shared](../../examples/shared/daemon.lua)
is a kernel script that implements an in-memory key-value store using
[rcu](https://luainkernel.github.io/lunatik/modules/rcu.html),
[data](https://luainkernel.github.io/lunatik/modules/data.html),
[socket](https://luainkernel.github.io/lunatik/modules/socket.html) and
[thread](https://luainkernel.github.io/lunatik/modules/thread.html).

### Usage

```
sudo make examples_install         # installs examples
sudo lunatik spawn examples/shared/daemon # spawns shared
nc 127.0.0.1 90                    # connects to shared
foo=bar                            # assigns "bar" to foo
foo                                # retrieves foo
bar
nokey                              # retrieves a key that was never assigned
                                   # answers with an empty line
^C                                 # finishes the connection
```

## echod

[echod](../../examples/echod)
is an echo server implemented as kernel scripts.

### Usage

```
sudo make examples_install               # installs examples
sudo lunatik spawn examples/echod/daemon # runs echod
nc 127.0.0.1 1337
hello kernel!
hello kernel!
```

## systrack

[systrack](../../examples/systrack/probe.lua)
is a kernel script that uses kprobes to count every system call on the
running architecture. [systrack/device](../../examples/systrack/device.lua)
exposes the live counters as a character device readable with `cat`.

The device runtime creates the probe runtime via `runner.run`, passing the
RCU counter table via `runtime:resume()`. Stopping the device runtime also
stops the probe runtime.

### Usage

```
sudo make examples_install                            # installs examples
sudo lunatik run examples/systrack/device             # starts device and probe runtimes
cat /dev/systrack
close: 473
openat: 515
read: 1066
write: 438
sudo lunatik stop examples/systrack/device            # stops device and probe runtimes
```

## dropreason

[dropreason](../../examples/dropreason/monitor.lua) answers "why is my packet dying?":
a kprobe on the out-of-line drop path reads the drop reason off the probed
function's arguments and counts the drops that reach it by name
(`linux.dropreason`) in an RCU table published on the shared environment
(`lunatik._ENV`). That path is `sk_skb_reason_drop(sk, skb, reason)` from v6.11,
where `kfree_skb_reason(skb, reason)` became a static inline over it, so the
script probes whichever symbol `linux.lookup()` finds and reads the reason from
the argument that goes with it; when neither exists, it names both instead of
failing as a registration error. A drop freed from hardirq
(`dev_kfree_skb_any()`) or as a segment list (`kfree_skb_list()`) takes another
path and is not counted.
[report](../../examples/dropreason/report.lua) reads those counts live from the REPL.
The script logs the symbol it settled on to `dmesg` as it arms, and the first
drop matching `WATCH` also has its registers and call trace dumped there, which
is what names the drop site.

### Usage

```
sudo make examples_install                            # installs examples
sudo lunatik run examples/dropreason/monitor hardirq  # arms the kprobe
echo x > /dev/udp/127.0.0.1/9999                      # trigger a NO_SOCKET drop
sudo lunatik                                          # opens the kernel REPL
> drops = require("examples.dropreason.report")
> drops.NO_SOCKET
1
> drops.report()                                      # counts by reason
      1  NO_SOCKET
      6  TCP_OLD_DATA
    152  NOT_SPECIFIED
sudo lunatik stop examples/dropreason/monitor
```

## netfailover

[netfailover](../../examples/netfailover) reroutes in reaction to a link: when the
watched interface (`dummy0`) goes down, a backup route to 192.0.2.1 is installed
in table 200 with `netlink.rt`, and removed when the link comes back up; each
change is announced on the `netfailover` family of a `netlink.channel`.
[control](../../examples/netfailover/control.lua) owns `notifier.netdevice`, whose
callback runs under RTNL, where a `netlink.rt` request is refused, so it only
records the link state in an `rcu.table`; [reactor](../../examples/netfailover/reactor.lua),
a spawned thread, polls that table and reprograms the route. They are two
runtimes because one would deadlock: the reactor holding the runtime lock while
it waits for RTNL, as the callback holds RTNL waiting for the runtime lock.

### Usage

```
sudo make examples_install                          # installs examples
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

## ifquarantine

[ifquarantine](../../examples/ifquarantine) composes two notifier chains to build
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

### Usage

```
sudo make examples_install                         # installs examples
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

## linkflap

[linkflap](../../examples/linkflap/watch.lua) detects an interface that flaps: a
`notifier.netdevice` callback keeps each interface's UP and DOWN transitions of
the last 10 seconds, the initial namespace's only since a homonym elsewhere
would announce under the same name, and once one interface reaches 5 it
multicasts a flapping event, the interface name and the transition count as
generic netlink attributes, on the `linkflap` family of a `netlink.channel`.
[subscriber](../../examples/linkflap/subscriber.c) joins that family's multicast group
from userspace and prints each event. The callback runs holding RTNL, which a
multicast does not take, so one runtime does both. Registering the notifier
replays an `UP` for each interface that already exists, one transition each.

### Usage

```
sudo make examples_install                             # installs examples
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

## filter

[filter](../../examples/filter) is a kernel extension composed by
a XDP/eBPF program to filter HTTPS sessions and
a Lua kernel script to filter [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) TLS extension.
This kernel extension drops any HTTPS request destinated to a
[blacklisted](../../examples/filter/sni.lua#L35) server.

### Usage

Usage requires `libbpf` and `bpftool` installed.

Come back to this repository, install and load the filter:

```sh
cd ${LUNATIK_DIR}/lunatik    # cf. above
sudo make btf_install        # needed to export the 'bpf_luaxdp_run' kfunc
sudo make examples_install   # installs examples
make ebpf                    # builds the XDP/eBPF program
sudo make ebpf_install       # installs the XDP/eBPF program
# Run the Lua kernel script, one runtime per CPU
sudo lunatik run examples/filter/sni softirq percpu
# Load the compiled XDP/eBPF program and attach to interface <ifname>
sudo bpftool prog load examples/filter/https.o /sys/fs/bpf/lunatik_filter type xdp
sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev <ifname>
```

For example, testing is easy thanks to [docker](https://www.docker.com).
Assuming docker is installed and running:

- in a terminal:
```sh
sudo bpftool prog load example/filter/https.o /sys/fs/bpf/lunatik_filter type xdp
sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev docker0
sudo journalctl -ft kernel
```
- in another one:
```sh
docker run --rm -it alpine/curl https://ebpf.io
```

The system logs (in the first terminal) should display `filter_sni: ebpf.io DROP`, and the
`docker run…` should return `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to ebpf.io:443`.

## filter in MoonScript

[This other sni filter](https://github.com/luainkernel/snihook) uses netfilter api.

## dnsblock

[dnsblock](../../examples/dnsblock) is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to filter DNS packets.
This script drops any outbound DNS packet with question matching the blacklist provided by the user. By default, it will block DNS resolutions for the domains `github.com` and `gitlab.com`.

### Usage

```
sudo make examples_install              # installs examples
sudo lunatik run examples/dnsblock/nf_dnsblock softirq	# runs the Lua kernel script
sudo lunatik run examples/dnsblock/nf_dnsblock softirq percpu	# or one runtime per CPU, sharing the hook
```

## dnsdoctor

[dnsdoctor](../../examples/dnsdoctor) is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to change the DNS response
from Public IP to a Private IP if the destination IP matches the one provided by the user. For example, if the user
wants to change the DNS response from `192.168.10.1` to `10.1.2.3` for the domain `lunatik.com` if the query is being sent to `10.1.1.2` (a private client), this script can be used.

### Usage

```
sudo make examples_install              # installs examples
examples/dnsdoctor/setup.sh             # sets up the environment

# test the setup, a response with IP 192.168.10.1 should be returned
dig lunatik.com

# run the Lua kernel script
sudo lunatik run examples/dnsdoctor/nf_dnsdoctor softirq
sudo lunatik run examples/dnsdoctor/nf_dnsdoctor softirq percpu	# or one runtime per CPU, sharing the hook

# test the setup, a response with IP 10.1.2.3 should be returned
dig lunatik.com

# cleanup
sudo lunatik unload
examples/dnsdoctor/cleanup.sh
```

## tcpreject

[tcpreject](../../examples/tcpreject) is a kernel script that uses the
netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html))
and the socket buffer API ([luaskb](https://luainkernel.github.io/lunatik/modules/skb.html))
to inject a TCP RST toward the origin of forwarded packets.

It intercepts packets marked by an `nft` rule, builds a RST+ACK by
copying the original packet, inverting IP, MAC, and port addresses,
trimming the payload, and recomputing the checksums.
It supports both IPv4 and IPv6.
By default, it rejects forwarded HTTPS (TCP/443) connections to `8.8.8.8` (IPv4)
and `2001:4860:4860::8888` (IPv6).

### Usage

```
sudo make examples_install              # installs examples
sudo examples/tcpreject/setup.sh        # sets up namespace, nft mark rule, and loads the hook

# connection is reset immediately (IPv4)
ip netns exec tcpreject curl --connect-timeout 2 https://8.8.8.8

# connection is reset immediately (IPv6)
ip netns exec tcpreject curl --connect-timeout 2 https://[2001:4860:4860::8888]

# cleanup
sudo examples/tcpreject/cleanup.sh
```

## sniclassify

[sniclassify](../../examples/sniclassify) is a kernel extension composed by
a TC/eBPF classifier program attached on egress,
a Lua kernel script to classify [SNI](https://datatracker.ietf.org/doc/html/rfc3546#section-3.1) traffic.
This kernel extension extracts server name and assigns traffic
classes according to a Lua [policy table](../../examples/sniclassify/sni.lua#L26).

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

## gesture

[gesture](../../examples/gesture/driver.lua)
is a kernel script that implements a HID driver for QEMU USB Mouse (0627:0001).
It supports gestures: swiping right locks the mouse, and swiping left unlocks it.

### Usage

1. You need to change the display protocal into `VNC` and enable USB mouse device in QEMU, the following configuration can help you disable PS2 mouse & enable USB mouse:

```
<features>
	<!-- ... -->
	<ps2 state="off"/>
	<!-- ... -->
</features>
```

2. run the gesture script:

```
sudo make examples_install 			# installs examples
sudo lunatik run examples/gesture/driver softirq 	# runs gesture
# In QEMU window:
# Drag right to lock the mouse
# Drag left to unlock the mouse
```

## xiaomi

[xiaomi](../../examples/xiaomi/driver.lua)
is a kernel script that ports the Xiaomi Silent Mouse driver to Lua using `luahid`.
It fixes the report descriptor for the device (`0x2717`:`0x5014`).

### Usage

```
sudo make examples_install 		# installs examples
sudo lunatik run examples/xiaomi/driver softirq 	# runs xiaomi driver
```

Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.

## lldpd

[lldpd](../../examples/lldpd/daemon.lua) shows how to implement a simple LLDP transmitter in kernel space using Lunatik.
It periodically emits LLDP frames on a given interface using an AF_PACKET socket.

### Usage

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

## cpuexporter

[cpuexporter](../../examples/cpuexporter/daemon.lua) will gather CPU usage statistics and expose using [OpenMetrics text format](https://github.com/prometheus/OpenMetrics/blob/main/specification/OpenMetrics.md#text-format) at the abstract UNIX socket `cpuexporter`, which leaves no file behind a stop.

### Usage

```shell
sudo make examples_install         	# installs examples
sudo lunatik spawn examples/cpuexporter/daemon # runs cpuexporter
sudo socat - ABSTRACT-CONNECT:cpuexporter <<<""
# TYPE cpu_usage_system gauge
cpu_usage_system{cpu="cpu1"} 0.0000000000000000 1764094519529162
cpu_usage_system{cpu="cpu0"} 0.0000000000000000 1764094519529162
# TYPE cpu_usage_idle gauge
cpu_usage_idle{cpu="cpu1"} 100.0000000000000000 1764094519529162
cpu_usage_idle{cpu="cpu0"} 100.0000000000000000 1764094519529162
...
```

## fsmonitor

[fsmonitor](../../examples/fsmonitor/monitor.lua) uses the `fsnotify` module to log what changes in one directory: an
entry created or deleted, a file written or its attributes changed, each line carrying the entry name,
its inode number and the pid that did it.

The mark is an inode mark on the directory `WATCHED` names, carrying `EVENT_ON_CHILD` so that events on
the files inside it are reported too. That flag is one level deep: nothing under a subdirectory arrives.
It also reaches a file only through its parent in the directory cache, so a write to a file opened by handle
with `open_by_handle_at` after the cache dropped its entry, or a change to its attributes, is not reported.

### Usage

```
sudo make examples_install                  # installs examples
mkdir -p /tmp/lunatik-fsmonitor             # the directory it watches
sudo lunatik run examples/fsmonitor/monitor # runs fsmonitor
touch /tmp/lunatik-fsmonitor/file
echo data > /tmp/lunatik-fsmonitor/file
rm /tmp/lunatik-fsmonitor/file
sudo lunatik stop examples/fsmonitor/monitor # stops fsmonitor
sudo dmesg -t                               # prints what it logged
fsmonitor: created file ino 13862 pid 2222346
fsmonitor: attributes file ino 13862 pid 2222346
fsmonitor: modified file ino 13862 pid 2222341
fsmonitor: modified file ino 13862 pid 2222341
fsmonitor: deleted file ino 13862 pid 2222347
```

The shell's redirection truncates the file on open and then writes it, so one command logs two
modifications; an event on the directory itself, its own `chmod` or `touch`, carries no entry name and
prints `?`.

## execguard

[execguard](../../examples/execguard/guard.lua) is an allowlist for `exec` over one directory: a permission event
parks the `execve` inside the callback, which refuses it unless the entry's name is in the `set` it was
built with.

A second list names who may run them: when the scope holds a file `pids` as the script starts, one pid per
line, the exec is refused to every pid it does not name. That pid is the one of the thread calling `execve`,
which after a `fork` is the child's: a shell the list names runs a program there only with `exec`, which
keeps its pid. Each refusal is logged with its reason, `not in the allowlist` or `pid not allowed`.

The mark is an inode mark on `SCOPE` carrying `EVENT_ON_CHILD`, so the only exec it can refuse is of an
entry directly inside that directory. It is never a system wide default deny: a `"mount"` or `"sb"` mark
reaches every file of a mount or of a whole filesystem, and a rule that denies there leaves the machine
unable to run the programs that would undo it. Give it a scratch mount of its own, as below, so that the
`umount` ends the rule even if the script cannot be stopped.

An exec opens more than the program for exec. Inside `execve` the kernel opens a script's interpreter, the
path on its `#!` line, and an ELF program's loader, the one absolute path `ldd` prints without `=>`, the
same way, and each asks the rule under its own name: a script whose interpreter lives in the scope is
refused unless that name is in the allowlist too. `strace -e openat` shows none of those opens; what it
shows, the loader reading its cache and the libraries and an interpreter reading its script, are reads that
never reach the rule. Landlock asks for its execute right at the same opens, so the programs, their loaders
and their interpreters are the list a Landlock ruleset grants it on as well. That is also why the rule stays
on a directory of its own: on the one holding `sh` or the loader, every script or every dynamically linked
program on the machine would have to pass the allowlist.

`EVENT_ON_CHILD` reaches the entry through its parent in the directory cache, so a program opened by handle
with `open_by_handle_at` after the cache dropped its entry, and run with `execveat` and `AT_EMPTY_PATH`, is
never asked about. That takes `CAP_DAC_READ_SEARCH`, and a filesystem that drops entries: the tmpfs below
keeps every entry it holds in the cache.

On a kernel built without `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`, which has no permission events, the script
still loads: it says so in the log and guards nothing.

### Usage

```
sudo make examples_install                  # installs examples
sudo mkdir -p -m 0755 /tmp/lunatik-execguard
sudo mount -t tmpfs -o size=1M,mode=0755 lunatik-execguard /tmp/lunatik-execguard
sudo cp /bin/true /bin/date /tmp/lunatik-execguard/
sudo lunatik run examples/execguard/guard   # runs execguard
/tmp/lunatik-execguard/true                 # "true" is in the allowlist: it runs
/tmp/lunatik-execguard/date                 # "date" is not
bash: /tmp/lunatik-execguard/date: Operation not permitted
sudo lunatik stop examples/execguard/guard  # ends the rule
sudo umount /tmp/lunatik-execguard          # and takes the mark with it
sudo dmesg -t                               # prints what it refused
execguard: denied date to pid 2222403: not in the allowlist
```

With a pid list:

```
sudo mount -t tmpfs -o size=1M,mode=0755 lunatik-execguard /tmp/lunatik-execguard
sudo cp /bin/true /tmp/lunatik-execguard/
bash                                        # a shell for the list to name
echo $$ | sudo tee /tmp/lunatik-execguard/pids
sudo lunatik run examples/execguard/guard   # reads the list as it starts
/tmp/lunatik-execguard/true                 # the child the shell forks has a pid of its own
bash: /tmp/lunatik-execguard/true: Operation not permitted
exec /tmp/lunatik-execguard/true            # runs in the listed pid, and ends that shell
sudo lunatik stop examples/execguard/guard
sudo umount /tmp/lunatik-execguard
sudo dmesg -t
execguard: denied true to pid 2222510: pid not allowed
```


