# Examples

Each example lives in a directory of `examples/`, with a README that says what it does and how to
run it. `sudo make install` puts them under `/lib/modules/lua/examples/`.

## Packet filtering and classification

* [filter](../../examples/filter): an XDP/eBPF program and a Lua script that filter HTTPS sessions by
  their SNI TLS extension. Needs clang, the libbpf headers, `bpftool` and a kernel with BTF.
* [dnsblock](../../examples/dnsblock): a netfilter hook that drops outbound DNS queries for blacklisted
  domains.
* [dnsdoctor](../../examples/dnsdoctor): a netfilter hook that rewrites the address in a DNS response
  for a private client. Needs `dnsmasq` and `dig`, and its `setup.sh` rewrites `/etc/resolv.conf`.
* [tcpreject](../../examples/tcpreject): a netfilter hook that injects a TCP RST toward the origin of
  forwarded packets an `nft` rule marks. Needs `nft`, and its `setup.sh` turns forwarding on.
* [sniclassify](../../examples/sniclassify): a TC/eBPF classifier on egress that classifies TLS
  traffic by SNI after a Lua policy table. Needs what filter needs, and its `setup.sh` replaces the
  interface's root qdisc with an HTB capped at 100 mbit.

## Network monitoring and control

* [tap](../../examples/tap): a sniffer on an `AF_PACKET` socket, read from a character device.
* [lldpd](../../examples/lldpd): an LLDP transmitter that periodically emits frames on an interface.
* [netfailover](../../examples/netfailover): installs a backup route when a watched interface goes
  down, and removes it when the link comes back.
* [ifquarantine](../../examples/ifquarantine): an interface-level default-deny policy built from two
  notifier chains.
* [linkflap](../../examples/linkflap): detects an interface that flaps and multicasts it as a generic
  netlink event.

## Servers and shared state

* [echod](../../examples/echod): an echo server as kernel scripts.
* [shared](../../examples/shared): an in-memory key-value store over an `rcu` table, served on a socket.
* [cpuexporter](../../examples/cpuexporter): CPU usage statistics in the Prometheus text format on an
  abstract UNIX socket.

## Tracing

* [systrack](../../examples/systrack): counts system calls with kprobes, one probe per syscall entry
  point no other syscall shares. Needs `CONFIG_KPROBES`.
* [dropreason](../../examples/dropreason): answers "why is my packet dying?" by counting drops by
  reason. Needs `CONFIG_KPROBES`.

## Input devices

* [spyglass](../../examples/spyglass): a keylogger inspired by the spy kernel module. Needs `CONFIG_VT`.
* [keylocker](../../examples/keylocker): locks and unlocks the console keyboard on the Konami Code.
  Needs `CONFIG_VT`.
* [gesture](../../examples/gesture): a HID driver for QEMU's USB tablet that locks and unlocks the
  pointer on a swipe.
* [xiaomi](../../examples/xiaomi): the Xiaomi Silent Mouse driver ported to Lua.

## Filesystem

* [fsmonitor](../../examples/fsmonitor): logs what changes in one directory.
* [execguard](../../examples/execguard): an allowlist for `exec` over one directory.

