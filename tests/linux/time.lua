--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.time test (see run.sh).
--

local linux   = require("linux")
local clock   = require("linux.clock")
local lunatik = require("lunatik")
local test    = require("tests.lib").test
local check   = require("tests.linux.check")

local format = string.format

local RECEIVER <const> = "tests/linux/time_recv"
local REFUSAL  <const> = "invalid clock"

-- the centisecond /proc/uptime truncates to, in nanoseconds
local CENTISECOND <const> = 10000000
-- the second /proc/stat's btime truncates to, in nanoseconds
local SECOND      <const> = 100 * CENTISECOND

local steady   <const> = {"MONOTONIC", "BOOTTIME"}
-- CLOCK_TAI, a clock linux.time does not read; an id no clock has; one past the int a clockid_t holds
local refused  <const> = {11, -1, 1 << 32}
local contexts <const> = {"softirq", "hardirq"}

local function uptime()
	local file <close> = assert(io.open("/proc/uptime"))
	local seconds, centiseconds = file:read("l"):match("^(%d+)%.(%d%d) ")
	return (tonumber(seconds) * 100 + tonumber(centiseconds)) * CENTISECOND
end

-- REALTIME less BOOTTIME, the boot time getboottime64() gives /proc/stat
local function btime()
	local file <close> = assert(io.open("/proc/stat"))
	return tonumber(file:read("a"):match("\nbtime (%d+)\n"))
end

test("linux.clock carries REALTIME, MONOTONIC and BOOTTIME at their uapi ids, and no other clock", function()
	check.holds("clock", clock, {"REALTIME", "MONOTONIC", "BOOTTIME"})
	check.carries("clock", clock, {REALTIME = 0, MONOTONIC = 1, BOOTTIME = 7})
end)

test("linux.time reads the real time given nothing or nil", function()
	local before = linux.time(clock.REALTIME)
	local none = linux.time()
	local null = linux.time(nil)
	local after = linux.time(clock.REALTIME)
	assert(before <= none and none <= null and null <= after,
		format("%d and %d fall outside the real time read around them, %d to %d", none, null, before, after))
end)

test("linux.time never decreases on MONOTONIC and BOOTTIME", function()
	for _, name in ipairs(steady) do
		local first = linux.time(clock[name])
		local second = linux.time(clock[name])
		assert(first <= second, format("%s went from %d back to %d", name, first, second))
	end
end)

test("linux.time reads MONOTONIC no later than BOOTTIME read after it", function()
	local mono = linux.time(clock.MONOTONIC)
	local boot = linux.time(clock.BOOTTIME)
	assert(mono <= boot, format("MONOTONIC %d is past BOOTTIME %d read after it", mono, boot))
end)

test("linux.time reads BOOTTIME between two reads of /proc/uptime", function()
	local before = uptime()
	local boot = linux.time(clock.BOOTTIME)
	local after = uptime() + CENTISECOND
	assert(before <= boot and boot < after,
		format("BOOTTIME %d falls outside /proc/uptime, %d to %d", boot, before, after))
end)

test("linux.time reads REALTIME ahead of BOOTTIME by the boot time /proc/stat shows", function()
	local boot = linux.time(clock.BOOTTIME)
	local real = linux.time(clock.REALTIME)
	local booted = btime()
	local ahead = (real - boot) // SECOND
	assert(booted <= ahead and ahead <= booted + 1,
		format("REALTIME %d is %d s ahead of BOOTTIME %d, where btime is %d", real, ahead, boot, booted))
end)

test("linux.time refuses a clock it does not read", function()
	for _, id in ipairs(refused) do
		local ok, err = pcall(linux.time, id)
		assert(not ok and err:find(REFUSAL, 1, true), format("linux.time(%d) answered %s", id, tostring(err)))
	end
end)

-- a runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("linux.time reads each clock from an armed softirq and an armed hardirq runtime", function()
	for _, context in ipairs(contexts) do
		local runtime <close> = lunatik.runtime(RECEIVER, context)
		local ok, err = pcall(runtime.resume, runtime)
		assert(ok, format("an armed %s runtime: %s", context, tostring(err)))
	end
end)

