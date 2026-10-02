--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Cases described in tests/signal/run.sh (signal/probe).

local probe  = require("probe")
local signal = require("signal")
local systab = require("syscall.table")

local INIT <const> = 1
local REFUSAL <const> = "not allowed with IRQs disabled"

assert(signal.kill(INIT, 0) == true, "kill(1, 0) should answer in the body, which runs with IRQs on")

local function pre()
	local ok, err = pcall(signal.kill, INIT, 0)
	print("signal probe: " .. ((not ok and err == REFUSAL) and "refused" or "answered"))
end

probe.new(systab["personality"], {pre = pre})

