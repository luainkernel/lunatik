--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor name test (see name.sh).

local lunatik = require("lunatik")
local fifo    = require("fifo")
local test    = require("tests.lib").test

local RAISE    <const> = "tests/monitor/name_raise"
local CAPACITY <const> = 16

local queue = fifo.new(CAPACITY)

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

