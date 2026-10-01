--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink rtnl test (see rtnl.sh).

local channel  = require("netlink.channel")
local notifier = require("notifier")
local notify   = require("linux.notify")

local FAMILY <const> = "lunatik_rtnl"
local HELD <const>   = "lunatik_held"
local PREFIX <const> = "netlink rtnl test: "
local CMD <const>    = 1

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local held = channel.new(HELD)
local probed = false

local function cb()
	if not probed then
		probed = true
		report("create " .. verdict(pcall(channel.new, FAMILY)))
		report("stop " .. verdict(pcall(held.stop, held)))
	end
	return notify.OK
end

notifier.netdevice(cb)
report("after " .. verdict(pcall(channel.new, FAMILY)))
report("multicast after " .. verdict(pcall(held.multicast, held, CMD)))
report("stop after " .. verdict(pcall(held.stop, held)))

