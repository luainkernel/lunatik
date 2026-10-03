--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Cases described in tests/signal/run.sh (signal/kill).

local lunatik = require("lunatik")
local linux   = require("linux")
local signal  = require("signal")
local sig     = require("linux.signal")
local pids    = require("tests.signal.pids")

local PAST_LIMIT <const> = (4 << 20) + 1 -- one past PID_MAX_LIMIT where it is largest, 64-bit
local WRAP <const> = 1 << 32
local SOFTIRQ <const> = "tests/signal/softirq"
local HARDIRQ <const> = "tests/signal/hardirq"
local AGAIN <const> = "tests/signal/again"
local IRQSOFF <const> = "hardirq"
local RETRIES <const> = 100
local PAUSE <const> = 10 -- ms, for the kernel worker to send the deferred TERM

local function resume(script, context)
	local runtime <close> = lunatik.runtime(script, context)
	runtime:resume()
end

local function deferagain()
	for _ = 1, RETRIES do
		if pcall(resume, AGAIN, IRQSOFF) then
			return true
		end
		linux.schedule(PAUSE)
	end
	return false
end

assert(signal.kill(pids.child, 0) == true, "kill(child, 0) should find the child")

local found, err = signal.kill(pids.reaped, 0)
assert(found == nil and err == "ESRCH",
	"a reaped pid should answer nil and ESRCH, got " .. tostring(found) .. ", " .. tostring(err))

local function refused(f, ...)
	local ok, err = pcall(f, ...)
	return not ok and err:match("out of bounds") ~= nil, err
end

for _, pid in ipairs({0, PAST_LIMIT, WRAP + pids.child}) do
	local ok, err = refused(signal.kill, pid, 0)
	assert(ok, "pid " .. pid .. " should be out of bounds, got " .. tostring(err))
end
for _, n in ipairs({-1, WRAP + sig.TERM}) do
	local ok, err = refused(signal.kill, pids.child, n)
	assert(ok, "signal " .. n .. " should be out of bounds, got " .. tostring(err))
end

resume(SOFTIRQ, "softirq")
resume(HARDIRQ, IRQSOFF)
assert(deferagain(), "a kill with IRQs off kept finding its CPU holding the TERM the worker sent")

assert(signal.kill(pids.child, sig.TERM) == true, "kill(child, TERM) should send the signal")

