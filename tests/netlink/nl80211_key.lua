--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink nl80211_key test (see nl80211_key.sh).

local netlink = require("netlink")
local iftype  = require("linux.nl80211").iftype
local cipher  = require("linux.nl80211").cipher

local NAME  <const> = "lunatikap0"
local SSID  <const> = "lunatik-test"
local RATES <const> = "\x82\x84\x8b\x96"                 -- 1, 2, 5.5, 11 Mbps
local GTK   <const> = ("\x11"):rep(16)

local pack = string.pack

local function beacon_head(bssid)
	return "\x80\x00" .. "\x00\x00" .. ("\xff"):rep(6) .. bssid .. bssid .. "\x00\x00"
		.. ("\x00"):rep(8) .. pack("<I2", 100) .. pack("<I2", 0x0001)
		.. string.char(0, #SSID) .. SSID .. "\x01\x04" .. RATES .. string.char(3, 1, 1)
end

-- an AP interface, up and beaconing, is the precondition for installing a key
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

local key <close> = netlink.nl80211.key()

-- a group key (GTK): no MAC, as hostapd installs it right after START_AP
key:add{ifindex = ifindex, index = 1, cipher = cipher.CCMP, data = GTK}
print("netlink nl80211_key: gtk installed")

-- an out-of-range key index must raise (NL80211_ATTR_KEY_IDX is capped at 7)
assert(not pcall(key.add, key,
	{ifindex = ifindex, index = 8, cipher = cipher.CCMP, data = GTK}),
	"out-of-range key index should raise")
print("netlink nl80211_key: bad index raises")

key:del{ifindex = ifindex, index = 1}
print("netlink nl80211_key: gtk removed")

