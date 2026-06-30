--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Input for autogen.lua. A spec is one of two kinds. A constant spec carries
-- a `prefix` and produces a table of integer constants (keyed by the constant
-- name with `prefix` stripped). A struct spec carries `struct` and `fields`
-- and produces a layout descriptor (per-field offset/size/signedness + total
-- size); `lib/struct.lua` turns that into a `string.pack` codec. Each entry
-- feeds one autogen/linux/<module>.lua.
--
-- @field header path relative to $(KBUILD)/include
-- @field module name of the resulting Lua module
-- @field desc   short LDoc description used by autogen/ldoc.lua
-- @field prefix constant prefix (constant specs)
-- @field struct kernel struct name (struct specs)
-- @field fields the struct's scalar fields (struct specs); order is free
--   (sorted by offset), but list them all, as gaps become padding and
--   non-scalar fields fail the build

return {
	{ header = "uapi/linux/if_ether.h",         prefix = "ETH_P_",     module = "eth",
		desc = "Ethernet protocol IDs." },
	{ header = "linux/stat.h",                  prefix = "S_",         module = "stat",
		desc = "File mode bits." },
	{ header = "uapi/linux/signal.h",           prefix = "SIG",        module = "signal",
		desc = "POSIX signal numbers." },
	{ header = "linux/notifier.h",              prefix = "NOTIFY_",    module = "notify",
		desc = "Return codes for kernel notifier chains." },
	{ header = "linux/notifier.h",              prefix = "KBD_",       module = "kbd",
		desc = "Keyboard notifier event types." },
	{ header = "linux/vt.h",                    prefix = "VT_",        module = "vt",
		desc = "Virtual terminal notifier event types." },
	{ header = "linux/netdevice.h",             prefix = "NETDEV_",    module = "netdev",
		desc = "Network device notifier event types." },
	{ header = "uapi/linux/bpf.h",              prefix = "XDP_",       module = "xdp",
		desc = "XDP verdicts and flags." },
	{ header = "linux/sched.h",                 prefix = "TASK_",      module = "task",
		desc = "Task state flags." },
	{ header = "linux/net.h",                   prefix = "SOCK_",      module = "socket.sock",
		desc = "Socket types (SOCK_STREAM, SOCK_DGRAM, ...)." },
	{ header = "linux/socket.h",                prefix = "AF_",        module = "socket.af",
		desc = "Socket address families." },
	{ header = "linux/socket.h",                prefix = "MSG_",       module = "socket.msg",
		desc = "Message flags for send/recv." },
	{ header = "uapi/linux/in.h",               prefix = "IPPROTO_",   module = "socket.ipproto",
		desc = "IP-layer protocol numbers." },
	{ header = "uapi/linux/netfilter.h",        prefix = "NFPROTO_",   module = "nf.proto",
		desc = "Netfilter protocol families." },
	{ header = "uapi/linux/netfilter.h",        prefix = "NF_INET_",   module = "nf.inet",
		desc = "Netfilter hook positions in the INET family." },
	{ header = "uapi/linux/netfilter.h",        prefix = "NF_NETDEV_", module = "nf.netdev",
		desc = "Netfilter hook positions in the NETDEV family." },
	{ header = "uapi/linux/netfilter_arp.h",    prefix = "NF_ARP_",    module = "nf.arp",
		desc = "Netfilter hook positions in the ARP family." },
	{ header = "uapi/linux/netfilter_ipv4.h",   prefix = "NF_IP_PRI_", module = "nf.ip.pri",
		desc = "Netfilter hook priorities in the IP family." },
	{ header = "uapi/linux/netfilter_bridge.h", prefix = "NF_BR_",     module = "nf.br",
		desc = "Netfilter hook positions in the BRIDGE family.",
		exclude = "NF_BR_PRI_" },
	{ header = "uapi/linux/netfilter_bridge.h", prefix = "NF_BR_PRI_", module = "nf.br.pri",
		desc = "Netfilter hook priorities in the BRIDGE family." },
	{ header = "uapi/linux/netfilter.h",        prefix = "NF_",        module = "nf.action",
		desc = "Netfilter hook verdicts.",
		include = { "DROP", "ACCEPT", "STOLEN", "QUEUE", "REPEAT", "STOP" } },
	{ header = "uapi/linux/netlink.h",          prefix = "NETLINK_",   module = "netlink.proto",
		desc = "Netlink protocol numbers.",
		include = { "ROUTE", "GENERIC" } },
	{ header = "asm/unistd.h",                  prefix = "__NR_",      module = "syscall.numbers",
		desc = "System call numbers (`__NR_*`) for the build arch.",
		exclude = { "__NR_arch_specific_syscall", "__NR_compat_", "__NR_syscalls",
			"__NR_x32_", "__NR_ia32_" } },
}

