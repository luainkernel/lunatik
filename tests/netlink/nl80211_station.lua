--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink nl80211_station test (see nl80211_station.sh).

local netlink = require("netlink")
local iftype  = require("linux.nl80211").iftype

local NAME  <const> = "lunatikap0"
local SSID  <const> = "lunatik-test"
local RATES <const> = "\x82\x84\x8b\x96"                 -- 1, 2, 5.5, 11 Mbps
local STA   <const> = string.char(0x02, 0, 0, 0, 0xaa, 0xbb)

local pack = string.pack

local function beacon_head(bssid)
	return "\x80\x00" .. "\x00\x00" .. ("\xff"):rep(6) .. bssid .. bssid .. "\x00\x00"
		.. ("\x00"):rep(8) .. pack("<I2", 100) .. pack("<I2", 0x0001)
		.. string.char(0, #SSID) .. SSID .. "\x01\x04" .. RATES .. string.char(3, 1, 1)
end

-- an AP interface, up and beaconing, is the precondition for adding a station
local ifindex, mac
do
	local wiphy     <close> = netlink.nl80211.wiphy()
	local interface <close> = netlink.nl80211.interface()
	ifindex = interface:add{wiphy = wiphy:list()[1].wiphy, name = NAME, iftype = iftype.AP}
	for _, iface in ipairs(interface:list()) do
		if iface.ifindex == ifindex then mac = iface.mac end
	end
end
netlink.rt.link():set{ifindex = ifindex, up = true}
local ap <close> = netlink.nl80211.ap()
ap:start{ifindex = ifindex, freq = 2412, beacon_interval = 100, dtim = 2,
	ssid = SSID, head = beacon_head(mac)}

local station <close> = netlink.nl80211.station()

local function present()
	for _, s in ipairs(station:list(ifindex)) do
		if s.mac == STA then return true end
	end
	return false
end

station:add{ifindex = ifindex, mac = STA, aid = 1, listen_interval = 10, supported_rates = RATES}
assert(present(), "station not listed after add")
print("netlink nl80211_station: added")

-- adding the same station again must raise
assert(not pcall(station.add, station,
	{ifindex = ifindex, mac = STA, aid = 1, listen_interval = 10, supported_rates = RATES}),
	"duplicate add should raise")
print("netlink nl80211_station: duplicate add raises")

station:set{ifindex = ifindex, mac = STA, authorized = true}
print("netlink nl80211_station: authorized")

station:del{ifindex = ifindex, mac = STA}
assert(not present(), "station still listed after del")
print("netlink nl80211_station: deleted")

