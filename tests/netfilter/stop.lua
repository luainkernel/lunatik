--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netfilter stop test (see stop.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local hooks     = require("tests.netfilter.hooks")

local PREFIX  <const> = "netfilter stop: "
local STOPPED <const> = 226
local CLOSED  <const> = 227
local KEPT    <const> = 228
local ONCE    <const> = 229

local once

local function report(skb)
	print(PREFIX .. skb:mark())
	return nf.action.ACCEPT
end

local function first(skb)
	once:stop()
	return report(skb)
end

local function register(hook, mark)
	return netfilter.register(hooks.localout(hook, mark))
end

local function scope(mark)
	local held <close> = register(report, mark)
	local class = getmetatable(held)
	assert(class.__close == class.stop, "a hook's __close is not its stop")
end

local stopped = register(report, STOPPED)
stopped:stop()
stopped:stop()

scope(CLOSED)
register(report, KEPT)
once = register(first, ONCE)

