--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netfilter verdict test (see verdict.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local action = nf.action

local PREFIX   <const> = "netfilter verdict: "
local RAISED   <const> = PREFIX .. "raised"
local KEPT     <const> = PREFIX .. "kept "
local REMARKED <const> = 219
local UNMARKED <const> = 225
local WIDEMARK <const> = 226
local WRAPPED  <const> = 1 << 32 -- DROP in its low 32 bits

local cases = {}

function cases.none()
end

function cases.boolean()
	return true
end

function cases.string()
	return tostring(action.DROP)
end

function cases.range()
	return action.STOP + 1
end

function cases.wrap()
	return WRAPPED
end

function cases.stolen()
	return action.STOLEN
end

function cases.repeated()
	return action.REPEAT
end

function cases.stop()
	return action.STOP
end

function cases.raise()
	error(RAISED, 0)
end

function cases.drop()
	return action.DROP
end

function cases.accept()
	return action.ACCEPT
end

function cases.queue()
	return action.QUEUE
end

function cases.remark()
	return action.ACCEPT, REMARKED
end

function cases.remarked()
	return action.DROP
end

function cases.unmarked()
	return action.ACCEPT, true
end

function cases.widemark()
	return action.ACCEPT, WRAPPED | REMARKED
end

local marks = {
	[211]      = "none",
	[212]      = "boolean",
	[213]      = "string",
	[214]      = "range",
	[215]      = "raise",
	[216]      = "drop",
	[217]      = "accept",
	[218]      = "remark",
	[REMARKED] = "remarked",
	[220]      = "wrap",
	[221]      = "stolen",
	[222]      = "repeated",
	[223]      = "stop",
	[224]      = "queue",
	[UNMARKED] = "unmarked",
	[WIDEMARK] = "widemark",
}

-- a hook later than the one that may store a mark, so the packet reaches it with the mark left
local LATER <const> = nf.ip.pri.FILTER + 1

local priorities = {remarked = LATER}

local function verdict(skb)
	local case = marks[skb:mark()]
	print(PREFIX .. case)
	return cases[case]()
end

local function kept(skb)
	print(KEPT .. skb:mark())
end

local function register(hook, mark, priority)
	netfilter.register{
		hook     = hook,
		pf       = nf.proto.INET,
		hooknum  = nf.inet.LOCAL_OUT,
		priority = priority,
		mark     = mark,
	}
end

for mark, case in pairs(marks) do
	register(verdict, mark, priorities[case] or nf.ip.pri.FILTER)
end

for _, mark in ipairs({UNMARKED, WIDEMARK}) do
	register(kept, mark, LATER)
end

