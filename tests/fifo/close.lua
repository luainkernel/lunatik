--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fifo close test (see run.sh).

local lunatik = require("lunatik")
local fifo    = require("fifo")
local test    = require("tests.lib").test

local RECEIVER <const> = "tests/fifo/close_recv"
local CAPACITY <const> = 1 << 20

local function closed(queue)
	local ok, err = pcall(queue.push, queue, "x")
	return not ok and err:match("closed object") ~= nil
end

test("fifo:close closes a fifo in a process runtime", function()
	local queue = fifo.new(CAPACITY)
	queue:close()
	assert(closed(queue), "the close left the fifo open")
end)

test("fifo:close closes a fifo in a softirq runtime past its body, with IRQs on", function()
	local queue = fifo.new(CAPACITY)
	local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
	runtime:resume(queue)
	assert(closed(queue), "the softirq runtime's close left the fifo open")
end)

