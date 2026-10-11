--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor name test (see name.sh).

local lunatik = require("lunatik")
local fifo    = require("fifo")
local test    = require("tests.lib").test

local sethook = debug.sethook

local RAISE    <const> = "tests/monitor/name_raise"
local CAPACITY <const> = 16
local NUMBER   <const> = 42
local CALLS    <const> = 3 -- pcall, the monitor and the method

local queue = fifo.new(CAPACITY)

local raised
local calls

local function hook()
	calls = calls + 1
	if calls == CALLS then
		error(raised)
	end
end

local function poperror(object)
	raised, calls = object, 0
	sethook(hook, "c")
	local ok, err = pcall(queue.pop, queue, 1)
	sethook()
	assert(not ok, "fifo:pop returned under a hook that raises")
	return err
end

test("a monitored method's raise names the method", function()
	local ok, err = pcall(queue.pop, queue, CAPACITY + 1)
	assert(not ok, "fifo:pop took a size past the capacity")
	assert(err == "bad argument #2 to 'pop' (out of bounds)", "fifo:pop raised " .. tostring(err))
end)

test("a resumed runtime's message reaches the caller of resume whole", function()
	local runtime <close> = lunatik.runtime(RAISE)
	local ok, err = pcall(runtime.resume, runtime)
	assert(not ok, "the resume of a body that raises returned")
	assert(err == "ready?\n", "resume raised " .. tostring(err))
end)

test("a monitored method's raise that is not a string reaches the caller as raised", function()
	local err = poperror(NUMBER) -- a build that rewrites a number fails here, before the table it would dereference
	assert(err == NUMBER, "fifo:pop raised a " .. type(err) .. " for a number")
	local object = {}
	err = poperror(object)
	assert(err == object, "fifo:pop raised " .. tostring(err) .. " for a table")
end)

