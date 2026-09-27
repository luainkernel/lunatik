# Examples

Each example lives in a directory of `examples/`, with a README that says what it does and how to
run it. `sudo make install` puts them under `/lib/modules/lua/examples/`.

## Packet filtering and classification

* [filter](../../examples/filter): an XDP/eBPF program and a Lua script that filter HTTPS sessions by
  their SNI TLS extension.
* [dnsblock](../../examples/dnsblock): a netfilter hook that drops outbound DNS queries for blacklisted
  domains.
* [dnsdoctor](../../examples/dnsdoctor): a netfilter hook that rewrites the address in a DNS response
  for a private client.
* [tcpreject](../../examples/tcpreject): a netfilter hook that injects a TCP RST toward the origin of
  forwarded packets an `nft` rule marks.
* [sniclassify](../../examples/sniclassify): a TC/eBPF classifier on egress that classifies TLS
  traffic by SNI after a Lua policy table.

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
* [cpuexporter](../../examples/cpuexporter): CPU usage statistics in OpenMetrics text format on a UNIX
  socket.

## Tracing

* [systrack](../../examples/systrack): counts every system call with kprobes.
* [dropreason](../../examples/dropreason): answers "why is my packet dying?" by counting drops by
  reason.

## Input devices

* [spyglass](../../examples/spyglass): a keylogger inspired by the spy kernel module.
* [keylocker](../../examples/keylocker): locks and unlocks the console keyboard on the Konami Code.
* [gesture](../../examples/gesture): a HID driver for QEMU's USB mouse that locks and unlocks it on a
  swipe.
* [xiaomi](../../examples/xiaomi): the Xiaomi Silent Mouse driver ported to Lua.

## Filesystem

* [fsmonitor](../../examples/fsmonitor): logs what changes in one directory.
* [execguard](../../examples/execguard): an allowlist for `exec` over one directory.

