--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Input for autogen.lua. Each entry produces one autogen/linux/<module>.lua
-- with integer constants matching `prefix` stripped from the Lua table key.
--
-- @field header path relative to $(KBUILD)/include
-- @field prefix constant prefix
-- @field module name of the resulting Lua module

return {
	{ header = "uapi/linux/if_ether.h",         prefix = "ETH_P_",     module = "eth"       },
	{ header = "linux/stat.h",                  prefix = "S_",         module = "stat"      },
	{ header = "uapi/linux/signal.h",           prefix = "SIG",        module = "signal"    },
	{ header = "linux/notifier.h",              prefix = "NOTIFY_",    module = "notify"    },
	{ header = "linux/notifier.h",              prefix = "KBD_",       module = "kbd"       },
	{ header = "linux/vt.h",                    prefix = "VT_",        module = "vt"        },
	{ header = "linux/netdevice.h",             prefix = "NETDEV_",    module = "netdev"    },
	{ header = "uapi/linux/bpf.h",              prefix = "XDP_",       module = "xdp"       },
	{ header = "linux/sched.h",                 prefix = "TASK_",      module = "task"      },
	{ header = "linux/net.h",                   prefix = "SOCK_",      module = "sock"      },
	{ header = "linux/socket.h",                prefix = "AF_",        module = "af"        },
	{ header = "linux/socket.h",                prefix = "MSG_",       module = "msg"       },
	{ header = "uapi/linux/in.h",               prefix = "IPPROTO_",   module = "ipproto"   },
	{ header = "uapi/linux/netfilter.h",        prefix = "NFPROTO_",   module = "nfproto"   },
	{ header = "uapi/linux/netfilter.h",        prefix = "NF_INET_",   module = "nf_inet"   },
	{ header = "uapi/linux/netfilter.h",        prefix = "NF_NETDEV_", module = "nf_netdev" },
	{ header = "uapi/linux/netfilter_arp.h",    prefix = "NF_ARP_",    module = "nf_arp"    },
	{ header = "uapi/linux/netfilter_ipv4.h",   prefix = "NF_IP_PRI_", module = "nf_ip_pri" },
	{ header = "uapi/linux/netfilter_bridge.h", prefix = "NF_BR_PRI_", module = "nf_br_pri" },
}

