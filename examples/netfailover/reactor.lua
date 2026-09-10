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

local WATCHED <const> = "dummy0"                  -- primary uplink to watch
local BACKUP  <const> = 200                       -- backup routing table id
local DST     <const> = string.char(192, 0, 2, 1) -- 192.0.2.1
local DST_LEN <const> = 32
local LO      <const> = 1                         -- loopback ifindex
local CMD     <const> = 1                         -- channel genl command
local POLL_MS <const> = 200

local function attacher()
	local route <close> = netlink.rt.route()
	local channel       = netlink.channel("netfailover")
	local active        = false
	while not thread.shouldstop() do
		local events = lunatik._ENV["netfailover"]
		local down = events and events[WATCHED]
		if down and not active then
			route:add{family = af.INET, dst = DST, dst_len = DST_LEN,
				oif = LO, table = BACKUP, scope = scope.LINK}
			channel:multicast(CMD, WATCHED .. " down: failover route installed")
			print("netfailover: " .. WATCHED .. " down -> backup route installed")
			active = true
		elseif not down and active then
			route:del{family = af.INET, dst = DST, dst_len = DST_LEN,
				oif = LO, table = BACKUP}
			channel:multicast(CMD, WATCHED .. " up: failover route removed")
			print("netfailover: " .. WATCHED .. " up -> backup route removed")
			active = false
		end
		linux.schedule(POLL_MS)
	end
end
return attacher

