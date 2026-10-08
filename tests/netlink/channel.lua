--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink channel test (see channel.sh).

local channel   = require("netlink.channel")
local message   = require("netlink.message")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local CMD, PAYLOAD = 1, 1        -- arbitrary genl command and attribute type
local UNICAST_PORT = 0x4c554e41  -- fixed port id the subscriber binds to
local ABSENT_PORT  = 0x7fffffff  -- unbound port id: a unicast to it must drop
local ARMED = "not allowed once the runtime is armed"
local OUTOFBOUNDS <const> = "out of bounds"
local BADNAME     <const> = "invalid family name length"
local U8          <const> = 1 << 8  -- past genlmsg_put's u8 command
local U32         <const> = 1 << 32 -- past the u32 port id
local FAMILY      <const> = "lunatiktest" -- FAMILY in channel.sh
local NAMSIZ      <const> = 16 -- GENL_NAMSIZ, the name and its terminator
local LONGEST     <const> = string.rep("x", NAMSIZ - 1) -- LONGEST in channel.sh

local function refuses(what, expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " was accepted")
	assert(tostring(err):find(expected, 1, true), what .. " raised something else: " .. tostring(err))
end

local family = channel.new(FAMILY)
local mcast = message.attrs{[PAYLOAD] = "channel multicast ok"}
local ucast = message.attrs{[PAYLOAD] = "channel unicast ok"}
local done = false

-- a header-only unicast to an absent port id is a dropped frame: false, no raise
assert(family:unicast(ABSENT_PORT, CMD) == false)
print("netlink channel: unicast to absent peer returns false")

-- each past 32 or 8 bits with low bits a truncating build sends to: the absent port id, or CMD
refuses("a port id past 32 bits", OUTOFBOUNDS, family.unicast, family, ABSENT_PORT | U32, CMD)
refuses("a negative port id", OUTOFBOUNDS, family.unicast, family, ABSENT_PORT - U32, CMD)
refuses("a unicast command past 8 bits", OUTOFBOUNDS, family.unicast, family, ABSENT_PORT, CMD | U8)
refuses("a multicast command past 8 bits", OUTOFBOUNDS, family.multicast, family, CMD | U8)
refuses("a negative multicast command", OUTOFBOUNDS, family.multicast, family, CMD - U8)
assert(family:unicast(U32 - 1, U8 - 1) == false)
family:multicast(U8 - 1)
print("netlink channel: a port id or command past its range is refused")

refuses("the port id 0, the kernel's", OUTOFBOUNDS, family.unicast, family, 0, CMD)
print("netlink channel: unicast to port id 0 is refused")

refuses("an empty name", BADNAME, channel.new, "")
refuses("a name of GENL_NAMSIZ bytes", BADNAME, channel.new, string.rep("x", NAMSIZ))
refuses("a registered name", "EEXIST", channel.new, FAMILY)
channel.new(LONGEST)
print("netlink channel: new refuses an empty, too long or registered name")

local function channel_hook()
	if not done then
		done = true
		local ok, err = pcall(channel.new, "")
		if not ok and err:find(ARMED, 1, true) then
			print("netlink channel: new from a hook is refused")
		end
	end
	family:multicast(CMD, mcast)
	family:unicast(UNICAST_PORT, CMD, ucast)
	return nf.action.ACCEPT
end

-- PRE_ROUTING on received (loopback) traffic runs in NET_RX softirq, so both
-- the multicast and the unicast are genuinely exercised from softirq context.
netfilter.register{
	hook     = channel_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.PRE_ROUTING,
	priority = nf.ip.pri.FILTER,
}

