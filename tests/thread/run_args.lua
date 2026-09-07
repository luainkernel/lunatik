--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver for the thread.run() arguments test (see run_args.sh).

local lunatik = require("lunatik")
local thread  = require("thread")
local fifo    = require("fifo")
local data    = require("data")
local linux   = require("linux")

local BODY <const> = "tests/thread/run_args_body"
local MARKER <const> = "run_args"
local NOTOBJECT <const> = 42
local TOKEN <const> = 7
local SIZE <const> = 8
local MANY <const> = 32
local TRIES <const> = 100
local PAUSE <const> = 10

local function assert_error(fn, pattern)
	local ok, err = pcall(fn)
	assert(not ok, "expected error but got none")
	assert(err:find(pattern), "unexpected error: " .. tostring(err))
end

local function newcontrol(extra)
	local control = data.new(SIZE)
	control:setbyte(0, TOKEN)
	control:setbyte(1, extra)
	return control
end

local function await(queue)
	for _ = 1, TRIES do
		if queue:pop(SIZE) == MARKER then
			return true
		end
		if thread.shouldstop() then
			return false
		end
		linux.schedule(PAUSE)
	end
	return false
end

local function driver()
	local queue = fifo.new(SIZE)
	local single = data.new(SIZE, "single")
	local runtime = lunatik.runtime(BODY)
	local stopped = lunatik.runtime(BODY)

	stopped:stop()

	assert_error(function() thread.run(runtime, MARKER, NOTOBJECT) end, "invalid object")
	assert_error(function() thread.run(runtime, MARKER, single) end, "cannot share SINGLE object")
	assert_error(function() thread.run(stopped, MARKER, queue) end, "stopped runtime")

	thread.run(runtime, MARKER, queue, newcontrol(0))
	assert(await(queue), "the thread body never pushed the marker for the objects it was given")

	local args = {lunatik.runtime(BODY), MARKER, queue, newcontrol(MANY)}
	for i = 1, MANY do
		table.insert(args, data.new(i))
	end
	thread.run(table.unpack(args))
	assert(await(queue), "the thread body did not get the objects past the ones a C function is entered with")

	print("run_args: PASS")
end

return driver

