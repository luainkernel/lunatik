--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the linux.time test (see run.sh).
--

local linux = require("linux")
local clock = require("linux.clock")

local format = string.format

local function read()
	local mono = linux.time(clock.MONOTONIC)
	local boot = linux.time(clock.BOOTTIME)
	local real = linux.time(clock.REALTIME)
	assert(mono <= boot, format("an armed runtime read MONOTONIC %d past BOOTTIME %d read after it", mono, boot))
	assert(real <= linux.time(), format("an armed runtime read the real time back from %d", real))
end

return read

