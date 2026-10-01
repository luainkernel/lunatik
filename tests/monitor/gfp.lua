--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitored allocation test (see gfp.sh).
--

local lunatik = require("lunatik")
local data    = require("data")
local fifo    = require("fifo")

local rep = string.rep

local RAISE   <const> = "tests/monitor/gfp_raise"
local FILL    <const> = "x"
local DATA    <const> = 2100
local FIFO    <const> = 2400
local SOFTIRQ <const> = 2700
local HARDIRQ <const> = 3000
local PROCESS <const> = 3300
local AFTER   <const> = 3600
local STRING  <const> = 3900

local function resume(context, length)
	local runtime <close> = lunatik.runtime(RAISE, context)
	assert(not pcall(runtime.resume, runtime, data.new(length)), context .. " runtime didn't raise")
end

data.new(DATA):getstring(0)
tostring(data.new(STRING))

local queue <close> = fifo.new(FIFO)
queue:push(rep(FILL, FIFO))
queue:pop(FIFO)

resume("process", PROCESS)
resume("softirq", SOFTIRQ)
resume("hardirq", HARDIRQ)

rep(FILL, AFTER)

