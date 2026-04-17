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
	{ header = "uapi/linux/if_ether.h", prefix = "ETH_P_",  module = "eth"    },
	{ header = "linux/stat.h",          prefix = "S_",      module = "stat"   },
	{ header = "uapi/linux/signal.h",   prefix = "SIG",     module = "signal" },
	{ header = "linux/notifier.h",      prefix = "NOTIFY_", module = "notify" },
	{ header = "linux/notifier.h",      prefix = "KBD_",    module = "kbd"    },
	{ header = "linux/vt.h",            prefix = "VT_",     module = "vt"     },
	{ header = "linux/netdevice.h",     prefix = "NETDEV_", module = "netdev" },
	{ header = "uapi/linux/bpf.h",      prefix = "XDP_",    module = "xdp"    },
	{ header = "linux/sched.h",         prefix = "TASK_",   module = "task"   },
}

