--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink nl80211_iface test (see nl80211_iface.sh).

local netlink = require("netlink")
local iftype  = require("linux.nl80211").iftype

local NAME <const> = "lunatikap0"

local interface <close> = netlink.nl80211.interface()

local wiphy_idx
do
	local wiphy <close> = netlink.nl80211.wiphy()
	wiphy_idx = wiphy:list()[1].wiphy
end

local function present(ifindex)
	for _, iface in ipairs(interface:list()) do
		if iface.ifindex == ifindex then return iface end
	end
end

local ifindex = interface:add{wiphy = wiphy_idx, name = NAME, iftype = iftype.AP}
assert(type(ifindex) == "number", "add did not return an ifindex")
local iface = present(ifindex)
assert(iface and iface.name == NAME and iface.iftype == iftype.AP, "added interface not an AP")
print("netlink nl80211_iface: AP interface added")

-- adding the same interface again must raise the kernel error
assert(not pcall(interface.add, interface, {wiphy = wiphy_idx, name = NAME, iftype = iftype.AP}),
	"duplicate add should raise")
print("netlink nl80211_iface: duplicate add raises")

interface:del{ifindex = ifindex}
assert(not present(ifindex), "interface still present after del")
print("netlink nl80211_iface: interface deleted")

