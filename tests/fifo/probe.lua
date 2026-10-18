--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Cases described in tests/fifo/run.sh (fifo/probe).

local fifo   = require("fifo")
local probe  = require("probe")
local systab = require("syscall.table")

local CAPACITY <const> = 16
local REFUSAL  <const> = "not allowed with IRQs disabled"

fifo.new(CAPACITY):close()

local queue = fifo.new(CAPACITY)

local function pre()
	local ok, err = pcall(queue.close, queue)
	print("fifo probe: " .. ((not ok and err == REFUSAL) and "refused" or "closed"))
end

probe.new(systab["personality"], {pre = pre})

