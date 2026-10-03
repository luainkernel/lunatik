--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Callback sub-script for signal/kill, resumed in a hardirq runtime after the first deferral (see run.sh).

local signal = require("signal")
local sig    = require("linux.signal")
local pids   = require("tests.signal.pids")

local function kill()
	assert(signal.kill(pids.child, sig.CONT) == true, "kill(child, CONT) should defer once the CPU's slot is free")
end

return kill

