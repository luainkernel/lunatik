--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local linux    = require("linux")
local netlink  = require("netlink")
local channel  = require("netlink.channel")
local notifier = require("notifier")
local netdev   = require("linux.netdev")
local af       = require("linux.socket").af
local scope    = require("linux.rtnetlink").scope

local format = string.format

local NAME    <const> = "netfailover"             -- the channel family
local WATCHED <const> = "dummy0"                  -- primary uplink to watch
local TABLE   <const> = 200                       -- backup routing table id
local DST     <const> = string.char(192, 0, 2, 1) -- 192.0.2.1
local DST_LEN <const> = 32
local LO      <const> = 1                         -- loopback ifindex
local CMD     <const> = 1                         -- channel genl command

local home <const> = linux.netns() -- the namespace the backup route is installed in

local backup = {
	family  = af.INET,
	dst     = DST,
	dst_len = DST_LEN,
	oif     = LO,
	table   = TABLE,
	scope   = scope.LINK,
}

local states = {[netdev.DOWN] = "down", [netdev.UP] = "up"}

local family = channel.new(NAME)
local route  = netlink.rt.route()

local reroute = {}

function reroute.down()
	route:add(backup)
	return "backup route installed"
end

function reroute.up()
	route:del(backup)
	return "backup route removed"
end

local function announce(state, change)
	local event = format("%s %s: %s", WATCHED, state, change)
	family:multicast(CMD, event)
	print("netfailover: " .. event)
end

local function callback(event, name, netns, replayed)
	local state = states[event]
	if state ~= nil and name == WATCHED and netns == home and not replayed then
		announce(state, reroute[state]())
	end
end

notifier.netdevice(callback)

