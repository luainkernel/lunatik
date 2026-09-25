--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink rtnl test (see rtnl.sh).

local netlink  = require("netlink")
local notifier = require("notifier")
local notify   = require("linux.notify")

local FAMILY <const> = "lunatik_rtnl"
local PREFIX <const> = "netlink rtnl test: "

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local probed = false

local function cb()
	if not probed then
		probed = true
		report("create " .. verdict(pcall(netlink.channel, FAMILY)))
	end
	return notify.OK
end

notifier.netdevice(cb)
report("after " .. verdict(pcall(netlink.channel, FAMILY)))

