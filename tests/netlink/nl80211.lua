--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink nl80211 test (see nl80211.sh).

local netlink = require("netlink")
local iftype  = require("linux.nl80211").iftype

local station = false
do
	local interface <close> = netlink.nl80211.interface()
	for _, iface in ipairs(interface:list()) do
		if iface.name and iface.name:match("^wlan") then
			assert(iface.ifindex and iface.wiphy and #iface.mac == 6, "interface fields incomplete")
			print("netlink nl80211: hwsim interface listed")
			if iface.iftype == iftype.STATION then station = true end
		end
	end
end
if station then
	print("netlink nl80211: interface is STATION")
end

do
	local wiphy <close> = netlink.nl80211.wiphy()
	-- radios=2: a broken fragment accumulation would still name one phy, not both
	local named = 0
	for _, phy in ipairs(wiphy:list()) do
		if phy.name then named = named + 1 end
	end
	assert(named >= 2, "expected at least 2 named wiphys, got " .. named)
	print("netlink nl80211: wiphys accumulated")
end

