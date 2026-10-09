--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.notifier test (see run.sh).
--

local netdev = require("linux.netdev").cmd
local vt     = require("linux.vt")
local test   = require("tests.lib").test
local check  = require("tests.linux.check")

-- enum netdev_cmd
local netdevs = {
	"UP", "DOWN", "REBOOT", "CHANGE", "REGISTER", "UNREGISTER", "CHANGEMTU", "CHANGEADDR", "PRE_CHANGEADDR",
	"GOING_DOWN", "CHANGENAME", "FEAT_CHANGE", "BONDING_FAILOVER", "PRE_UP", "PRE_TYPE_CHANGE",
	"POST_TYPE_CHANGE", "POST_INIT", "PRE_UNINIT", "RELEASE", "NOTIFY_PEERS", "JOIN", "CHANGEUPPER",
	"RESEND_IGMP", "PRECHANGEMTU", "CHANGEINFODATA", "BONDING_INFO", "PRECHANGEUPPER", "CHANGELOWERSTATE",
	"UDP_TUNNEL_PUSH_INFO", "UDP_TUNNEL_DROP_INFO", "CHANGE_TX_QUEUE_LEN", "CVLAN_FILTER_PUSH_INFO",
	"CVLAN_FILTER_DROP_INFO", "SVLAN_FILTER_PUSH_INFO", "SVLAN_FILTER_DROP_INFO", "OFFLOAD_XSTATS_ENABLE",
	"OFFLOAD_XSTATS_DISABLE", "OFFLOAD_XSTATS_REPORT_USED", "OFFLOAD_XSTATS_REPORT_DELTA", "XDP_FEAT_CHANGE",
}

-- the events of <linux/vt.h>, beside the names of <uapi/linux/vt.h> that share their prefix
local vts = { "ALLOCATE", "DEALLOCATE", "WRITE", "UPDATE", "PREWRITE" }

test("linux.netdev.cmd carries the netdevice notifier events and nothing else", function()
	check.holds("netdev.cmd", netdev, netdevs)
end)

test("linux.vt carries the vt notifier events and nothing else", function()
	check.holds("vt", vt, vts)
end)

