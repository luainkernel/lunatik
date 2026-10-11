--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor hook test (see hook.sh).

local fifo  = require("fifo")
local linux = require("linux")
local test  = require("tests.lib").test

local sethook = debug.sethook
local getinfo = debug.getinfo
local concat  = table.concat
local insert  = table.insert

local CAPACITY <const> = 16
local COUNT    <const> = 100
local TURNS    <const> = 1000
local SLEEP    <const> = 1
local ITEM     <const> = "x"

local queue = fifo.new(CAPACITY)
local names = {[queue.push] = "push", [queue.pop] = "pop", [pcall] = "pcall"}

local expected <const> = {
	c  = "call push, call pop",
	r  = "return push, return pop",
	cr = "call push, return push, call pop, return pop",
}

local seen
local sleeping
local fired

local function record(event)
	local info = getinfo(2, "Sf")
	if info.what == "C" and info.func ~= sethook then
		insert(seen, event .. " " .. (names[info.func] or "?"))
	end
	if sleeping then
		linux.schedule(SLEEP)
	end
end

local function tick()
	fired = fired + 1
end

local function pushpop()
	queue:push(ITEM)
	queue:pop(#ITEM)
end

local function overflow()
	pcall(queue.pop, queue, CAPACITY + 1)
	queue:push(ITEM)
end

-- the events a hook of mask records for the C functions body calls, "?" for one body does not call
local function trace(mask, body, sleep)
	seen, sleeping = {}, sleep
	sethook(record, mask)
	body()
	sethook()
	return concat(seen, ", ")
end

test("a call or return hook sees a monitored method's call and return and not the method's own", function()
	for mask, events in pairs(expected) do
		local traced = trace(mask, pushpop)
		assert(traced == events, "a hook of mask '" .. mask .. "' saw " .. traced)
	end
end)

test("a call or return hook stays set after a monitored method raises", function()
	local traced = trace("cr", overflow)
	assert(traced == "call pcall, call pop, return pcall, call push, return push", "the hook saw " .. traced)
end)

test("a count hook keeps counting across monitored methods", function()
	fired = 0
	sethook(tick, "", COUNT)
	for _ = 1, TURNS do
		pushpop()
	end
	sethook()
	assert(fired > 0, "a count hook of " .. COUNT .. " never fired over " .. TURNS .. " pushes and pops")
end)

test("a hook that sleeps on every event runs outside a monitored method's lock", function()
	local traced = trace("cr", pushpop)
	assert(traced == expected.cr, "the hook runs under the lock, where it would sleep: it saw " .. traced)
	traced = trace("cr", pushpop, true)
	assert(traced == expected.cr, "a hook that sleeps saw " .. traced)
end)

