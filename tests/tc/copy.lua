--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc copy cases (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local format = string.format

local REFUSAL <const> = "skb has no device"

local order = {"inside", "past", "detach"}
local steps = {}
local copies = {}
local hook = setmetatable({}, {__mode = "v"})
local step = 0

local function report(cell, failure)
	print("tc copy: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

-- a copy inside the callback names the device of the hook's skb
local function keep(skb)
	local copy = skb:copy()
	local index, want = copy:ifindex(), skb:ifindex()
	return {copy = copy, length = #skb}, index ~= want and format("ifindex %s, not %d", index, want)
end

-- a copy past its callback: no device, forward() refused, its bytes read
local function answers(kept)
	local copy = kept.copy
	local index = copy:ifindex()
	if index ~= nil then
		return "ifindex " .. index
	end
	local ok, err = pcall(copy.forward, copy)
	if ok then
		return "forward() sent it"
	elseif not err:find(REFUSAL, 1, true) then
		return err
	end
	local data = copy:data()
	local size = #data
	if size ~= kept.length or not packet.isping(data) then
		return format("a view of %d bytes, not the echo reply of %d", size, kept.length)
	end
end

local function detached(ctx)
	if packet.isping(ctx:skb():data()) then
		report("detached", answers(copies.detached))
	end
	return action.OK
end

function steps.inside(ctx)
	local failure
	copies.past, failure = keep(ctx:skb())
	return failure
end

function steps.past()
	return answers(copies.past)
end

function steps.detach(ctx)
	local skb = ctx:skb()
	local failure
	copies.detached, failure = keep(skb)
	hook.skb, skb = skb, nil -- past tc.detach(), only the weak hook holds it: collectgarbage() runs its __gc
	tc.detach()
	tc.attach(detached)
	collectgarbage()
	return failure or hook.skb and "the hook's skb outlived the collection"
end

local function test_copy(ctx)
	if not packet.isping(ctx:skb():data()) then
		return action.OK
	end
	step = step + 1
	local cell = order[step]
	report(cell, steps[cell](ctx))
	return action.OK
end

tc.attach(test_copy)

