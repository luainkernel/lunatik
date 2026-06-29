--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink channel test (see channel.sh).

local netlink   = require("netlink")
local message   = require("netlink.message")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local CMD, PAYLOAD = 1, 1        -- arbitrary genl command and attribute type
local UNICAST_PORT = 0x4c554e41  -- fixed port id the subscriber binds to
local ABSENT_PORT  = 0x7fffffff  -- unbound port id: a unicast to it must drop

local channel = netlink.channel("lunatiktest")
local bcast = message.attrs{[PAYLOAD] = "channel broadcast ok"}
local ucast = message.attrs{[PAYLOAD] = "channel unicast ok"}

-- a header-only unicast to an absent port id is a dropped frame: false, no raise
assert(channel:unicast(ABSENT_PORT, CMD) == false)
print("netlink channel: unicast to absent peer returns false")

local function channel_hook(skb)
	channel:broadcast(CMD, bcast)
	channel:unicast(UNICAST_PORT, CMD, ucast)
	return nf.action.ACCEPT
end

-- PRE_ROUTING on received (loopback) traffic runs in NET_RX softirq, so both
-- the broadcast and the unicast are genuinely exercised from softirq context.
netfilter.register{
	hook     = channel_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.PRE_ROUTING,
	priority = nf.ip.pri.FILTER,
}

