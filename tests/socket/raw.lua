--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket.raw test (see raw.sh).

local raw   = require("socket.raw")
local linux = require("linux")
local eth   = require("linux.eth")

local format = string.format

local PROTO  <const> = eth["802_EX1"]
local IFNAME <const> = "lo"
-- the largest interface index the binding takes, which no device holds
local ABSENT <const> = 0x7FFFFFFF

local function say(what)
	print("socket raw: " .. what)
end

local function binds(...)
	local s <close> = raw.new(...)
	return format("binds %04x on %d", s:getsockname())
end

local function raises(...)
	local ok, s = pcall(raw.new, ...)
	if ok then
		s:close()
	end
	return ok and "binds" or "raises " .. tostring(s)
end

local ifindex = linux.ifindex(IFNAME)

say("new " .. binds(PROTO, ifindex))
say("new with no interface " .. binds(PROTO))
say("new with no ethertype " .. binds(nil, ifindex))
say("new with no argument " .. binds())

say("new on an absent interface " .. raises(PROTO, ABSENT))
say("new on a negative interface " .. raises(PROTO, -1))

