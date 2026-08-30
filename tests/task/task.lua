--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the task test (see run.sh). Runs in process
-- context, so task.current() refers to the `lunatik` CLI process that
-- issued this script through the device's write(2) callback.
--

local task = require("task")
local cpu  = require("cpu")
local test = require("util").test

test("task.current() returns a task object", function()
	local t = task.current()
	assert(t ~= nil, "current() returned nil")
end)

test("comm() reports the caller's command name", function()
	local t = task.current()
	local comm = t:comm()
	assert(type(comm) == "string", "comm(): expected string, got " .. type(comm))
	assert(comm == "lunatik", "comm(): expected 'lunatik', got '" .. comm .. "'")
end)

test("pid() and tgid() are positive and match for the (single-threaded) caller", function()
	local t = task.current()
	local pid, tgid = t:pid(), t:tgid()
	assert(type(pid) == "number" and pid > 0, "pid(): expected positive number, got " .. tostring(pid))
	assert(type(tgid) == "number" and tgid > 0, "tgid(): expected positive number, got " .. tostring(tgid))
	assert(pid == tgid, "pid/tgid mismatch for main thread: " .. pid .. " ~= " .. tgid)
end)

test("prio() is within the kernel's dynamic priority range", function()
	local t = task.current()
	local prio = t:prio()
	assert(type(prio) == "number", "prio(): expected number, got " .. type(prio))
	assert(prio >= 0 and prio <= 139, "prio(): out of range [0, 139]: " .. prio)
end)

test("cpu() reports a valid online CPU index", function()
	local t = task.current()
	local online = cpu.num_online()
	local c = t:cpu()
	assert(type(c) == "number", "cpu(): expected number, got " .. type(c))
	assert(c >= 0 and c < online, "cpu(): out of range [0, " .. online .. "): " .. c)
end)

test("independent current() calls agree and survive garbage collection", function()
	local a, b = task.current(), task.current()
	assert(a:pid() == b:pid(), "pid mismatch across current() calls")
	a = nil
	collectgarbage()
	assert(b:pid() > 0, "second object unusable after the first was collected")
end)

