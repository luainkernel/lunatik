--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local netlink = require("netlink")
local thread  = require("thread")
local linux   = require("linux")
local af      = require("linux.socket").af
local scope   = require("linux.rtnetlink").scope

local format = string.format

local NAME    <const> = "netfailover"             -- the table control.lua shares, and the channel family
local WATCHED <const> = "dummy0"                  -- primary uplink to watch
local TABLE   <const> = 200                       -- backup routing table id
local DST     <const> = string.char(192, 0, 2, 1) -- 192.0.2.1
local DST_LEN <const> = 32
local LO      <const> = 1                         -- loopback ifindex
local CMD     <const> = 1                         -- channel genl command
local POLL_MS <const> = 200

local backup = {
	family  = af.INET,
	dst     = DST,
	dst_len = DST_LEN,
	oif     = LO,
	table   = TABLE,
	scope   = scope.LINK,
}

local channel = netlink.channel(NAME)

local reroute = {}

function reroute.down(route)
	route:add(backup)
	return "backup route installed"
end

function reroute.up(route)
	route:del(backup)
	return "backup route removed"
end

local function isdown()
	local events = lunatik._ENV[NAME]
	return events ~= nil and events[WATCHED] ~= nil
end

local function announce(state, change)
	local event = format("%s %s: %s", WATCHED, state, change)
	channel:multicast(CMD, event)
	print("netfailover: " .. event)
end

local function react()
	local route <close> = netlink.rt.route()
	local rerouted = false
	while not thread.shouldstop() do
		local down = isdown()
		if down ~= rerouted then
			local state = down and "down" or "up"
			announce(state, reroute[state](route))
			rerouted = down
		end
		linux.schedule(POLL_MS)
	end
end

return react

