--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Cases described in tests/runtime/close_irqs.sh (runtime/close_irqs/softirq).

local lunatik = require("lunatik")
local fifo    = require("fifo")

local RECEIVER <const> = "tests/runtime/close_irqs_softirq"
local CAPACITY <const> = 16

local function closed(queue)
	local ok, err = pcall(queue.push, queue, "x")
	return not ok and tostring(err):match("closed object") ~= nil
end

local queue, scoped = fifo.new(CAPACITY), fifo.new(CAPACITY)
local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
runtime:resume(queue, scoped)
assert(closed(queue), "a softirq runtime's callback left the fifo it closed open")
assert(closed(scoped), "a softirq runtime's callback left the fifo its to-be-closed variable held open")

