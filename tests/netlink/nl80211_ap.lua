--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink nl80211_ap test (see nl80211_ap.sh).

local netlink = require("netlink")
local iftype  = require("linux.nl80211").iftype

local NAME <const> = "lunatikap0"
local SSID <const> = "lunatik-test"
local FREQ <const> = 2412  -- 2.4 GHz channel 1
local BINT <const> = 100   -- beacon interval (TUs)
local CHAN <const> = 1

local pack = string.pack

-- a minimal open-AP beacon frame up to the TIM element (which the kernel adds)
local function beacon_head(bssid)
	return "\x80\x00"                     -- frame control: beacon
		.. "\x00\x00"                     -- duration
		.. ("\xff"):rep(6)                -- addr1: broadcast
		.. bssid                          -- addr2: BSSID
		.. bssid                          -- addr3: BSSID
		.. "\x00\x00"                     -- sequence control
		.. ("\x00"):rep(8)                -- timestamp (set by hardware)
		.. pack("<I2", BINT)              -- beacon interval
		.. pack("<I2", 0x0001)            -- capability info: ESS
		.. string.char(0, #SSID) .. SSID  -- SSID element
		.. "\x01\x04\x82\x84\x8b\x96"     -- supported rates: 1, 2, 5.5, 11 Mbps
		.. string.char(3, 1, CHAN)        -- DS parameter set: channel
end

local ifindex, mac
do
	local wiphy     <close> = netlink.nl80211.wiphy()
	local interface <close> = netlink.nl80211.interface()
	ifindex = interface:add{wiphy = wiphy:list()[1].wiphy, name = NAME, iftype = iftype.AP}
	for _, iface in ipairs(interface:list()) do
		if iface.ifindex == ifindex then mac = iface.mac end
	end
end
assert(mac, "AP interface has no MAC")

local link <close> = netlink.rt.link()
link:set{ifindex = ifindex, up = true}

local ap <close> = netlink.nl80211.ap()
local params = {ifindex = ifindex, freq = FREQ, beacon_interval = BINT, dtim = 2,
	ssid = SSID, head = beacon_head(mac)}
ap:start(params)
print("netlink nl80211_ap: AP started")

-- starting an already-beaconing AP must raise
assert(not pcall(ap.start, ap, params), "second start should raise")
print("netlink nl80211_ap: second start raises")

ap:stop{ifindex = ifindex}
print("netlink nl80211_ap: AP stopped")

link:set{ifindex = ifindex, up = false}
do
	local interface <close> = netlink.nl80211.interface()
	interface:del{ifindex = ifindex}
end

