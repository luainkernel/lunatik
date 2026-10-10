--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor name test (see name.sh).

local fifo = require("fifo")
local test = require("tests.lib").test

local CAPACITY <const> = 16

local queue = fifo.new(CAPACITY)

test("a monitored method's raise names the method", function()
	local ok, err = pcall(queue.pop, queue, CAPACITY + 1)
	assert(not ok, "fifo:pop took a size past the capacity")
	assert(err == "bad argument #2 to 'pop' (out of bounds)", "fifo:pop raised " .. tostring(err))
end)

