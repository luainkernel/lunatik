--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Callback sub-script for signal/kill, resumed in a softirq runtime (see run.sh).

local signal = require("signal")
local sig    = require("linux.signal")
local pids   = require("tests.signal.pids")

local function kill()
	assert(signal.kill(pids.child, sig.CONT) == true, "kill(child, CONT) should send the signal with IRQs on")
	assert(signal.kill(pids.child, sig.CONT) == true, "a second kill(child, CONT) should send in place too")
end

return kill

