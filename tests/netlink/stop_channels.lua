--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Script of the runtimes the netlink stop test creates (see stop.sh).

local channel = require("netlink.channel")

local CMD <const>    = 1
local PORT <const>   = 1
local CLOSED <const> = "closed object"

local function raises(method, ...)
	local ok, err = pcall(method, ...)
	return not ok and err:find(CLOSED, 1, true) ~= nil
end

local function scope(name)
	local held <close> = channel.new(name)
	local class = getmetatable(held)
	assert(class.__close == class.stop, "a channel's __close is not its stop")
end

local stopped = channel.new("lunatik_stopped")
stopped:stop()
stopped:stop()
if raises(stopped.multicast, stopped, CMD) and raises(stopped.unicast, stopped, PORT, CMD) then
	print("netlink stop test: a stopped channel raises")
end

scope("lunatik_closed")

local kept = channel.new("lunatik_kept")

local function armed()
	kept:stop()
end

return armed

