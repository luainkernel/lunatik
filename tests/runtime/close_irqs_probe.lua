--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Cases described in tests/runtime/close_irqs.sh (runtime/close_irqs/probe).

local fifo   = require("fifo")
local probe  = require("probe")
local systab = require("syscall.table")

local CAPACITY <const> = 16
local REFUSAL  <const> = "not allowed with IRQs disabled"

local function scope(queue)
	local held <close> = queue
end

local function refused(close, queue)
	local ok, err = pcall(close, queue)
	return not ok and tostring(err):find(REFUSAL, 1, true) ~= nil
end

fifo.new(CAPACITY):close()
scope(fifo.new(CAPACITY))

local queue = fifo.new(CAPACITY)

local function pre()
	local kept = refused(queue.close, queue) and refused(scope, queue) and pcall(queue.push, queue, "x")
	print("close_irqs probe: " .. (kept and "refused" or "closed"))
end

probe.new(systab["personality"], {pre = pre})

