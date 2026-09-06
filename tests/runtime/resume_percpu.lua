--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the percpu resume test (see resume_percpu.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local rcu     = require("rcu")
local test    = require("util").test

local SCRIPT <const> = "tests/runtime/resume_percpu_recv"
local FAILING <const> = "tests/runtime/resume_percpu_fail"
local IRQ <const> = "tests/runtime/resume_percpu_irq"
local ANSWER <const> = 42

test("resume delivers the same object to every runtime", function()
	local seen = rcu.table()
	local runtimes <close> = lunatik.percpu(SCRIPT)
	runtimes:resume(seen)
	for cpu = 0, linux.numcpus() - 1 do
		assert(seen[tostring(cpu)], "runtime " .. cpu .. " did not receive the object")
	end
	assert(select("#", runtimes:resume()) == 0, "resume returned what a runtime yielded")
	for cpu = 0, linux.numcpus() - 1 do
		assert(seen[tostring(cpu)] == nil, "runtime " .. cpu .. " was not resumed past its yield")
	end
end)

test("resume delivers to the runtimes of a softirq set", function()
	local seen = rcu.table()
	local runtimes <close> = lunatik.percpu(SCRIPT, "softirq")
	runtimes:resume(seen)
	for cpu = 0, linux.numcpus() - 1 do
		assert(seen[tostring(cpu)], "softirq runtime " .. cpu .. " did not receive the object")
	end
end)

test("resume delivers every object it is given, in order", function()
	local first, second = rcu.table(), rcu.table()
	local runtimes <close> = lunatik.percpu(SCRIPT)
	runtimes:resume(first, second)
	for cpu = 0, linux.numcpus() - 1 do
		local id = tostring(cpu)
		assert(first[id] == 1 and second[id] == 2, "runtime " .. cpu .. " did not receive both objects in order")
	end
end)

test("resume delivers to the runtimes of a hardirq set", function()
	local runtimes <close> = lunatik.percpu(IRQ, "hardirq")
	runtimes:resume(rcu.table())
	local ok, err = pcall(runtimes.resume, runtimes)
	assert(not ok, "a hardirq runtime accepted a resume that delivered nothing")
	assert(err:match("nothing was delivered"), "resume raised something else: " .. tostring(err))
	assert(err:match("cpu %d+"), "the error does not name the CPU: " .. tostring(err))
end)

test("resume raises what a runtime raises", function()
	local runtimes <close> = lunatik.percpu(FAILING)
	local ok, err = pcall(runtimes.resume, runtimes, rcu.table())
	assert(not ok, "resume accepted a script that errors")
	assert(err:match("intentional error on resumption"), "resume raised something else: " .. tostring(err))
	assert(err:match("cpu %d+"), "the error does not name the CPU: " .. tostring(err))
	local again = select(2, pcall(runtimes.resume, runtimes, rcu.table()))
	assert(again:match("cannot resume dead coroutine"), "the raising runtime was left resumable: " .. tostring(again))
end)

test("resume refuses a value that is not an object", function()
	local runtimes <close> = lunatik.percpu(SCRIPT)
	local ok, err = pcall(runtimes.resume, runtimes, ANSWER)
	assert(not ok, "resume accepted a value that is not an object")
	assert(err:match("invalid object"), "resume raised something else: " .. tostring(err))
	assert(err:match("cpu %d+"), "the error does not name the CPU: " .. tostring(err))
	local seen = rcu.table()
	runtimes:resume(seen)
	assert(seen["0"], "runtime 0 was not resumable after the refusal")
end)

test("resume refuses a stopped object", function()
	local runtimes = lunatik.percpu(SCRIPT)
	runtimes:stop()
	local ok, err = pcall(runtimes.resume, runtimes, rcu.table())
	assert(not ok, "resume accepted a stopped object")
	assert(err:match("null pointer"), "resume raised something else: " .. tostring(err))
end)

test("resume refuses a percpu object of another class", function()
	local runtimes <close> = lunatik.percpu(SCRIPT)
	local ok, err = pcall(getmetatable(runtimes).resume, rcu.table(), rcu.table())
	assert(not ok, "resume accepted an object of another class")
	assert(err:match("percpu expected"), "resume raised something else: " .. tostring(err))
end)

