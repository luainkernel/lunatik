--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict cases (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc")
local packet = require("tests.tc.packet")

local PREFIX  <const> = "tc verdict: "
local RAISED  <const> = PREFIX .. "raised"
local BELOW   <const> = -2 -- below every action, and apart from the -1 a refusal answers
local HEADERS <const> = 42 -- Ethernet, IPv4 and ICMP, before the ping's payload
local WRAPPED <const> = (1 << 32) | action.ACT_SHOT

local cases = {}

function cases.none()
end

function cases.boolean()
	return true
end

function cases.string()
	return tostring(action.ACT_SHOT)
end

function cases.range()
	return action.ACT_VALUE_MAX + 1
end

function cases.wrap()
	return WRAPPED
end

function cases.raise()
	error(RAISED, 0)
end

function cases.below()
	return BELOW
end

-- the ping's payload size picks the case, as VERDICT_PAYLOADS in test_tc.sh lists them
local payloads = {
	[101] = "none",
	[102] = "boolean",
	[103] = "string",
	[104] = "range",
	[105] = "wrap",
	[106] = "raise",
	[107] = "below",
}

local function verdict(ctx)
	local skb  = ctx:skb()
	local case = packet.isping(skb:data()) and payloads[#skb - HEADERS]
	if not case then
		return action.ACT_OK
	end
	print(PREFIX .. case)
	return cases[case]()
end

tc.attach(verdict)

