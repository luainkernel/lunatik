--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Callback sub-script for signal/kill, resumed in a hardirq runtime (see run.sh).

local signal = require("signal")
local sig    = require("linux.signal")
local pids   = require("tests.signal.pids")

local function kill()
	assert(signal.kill(pids.deferred, sig.TERM) == true, "kill(deferred, TERM) should defer the signal")
	assert(signal.kill(pids.deferred, sig.TERM) == false, "a second kill should find the CPU holding the first")
	assert(signal.kill(pids.deferred, 0) == true, "kill(deferred, 0) should find the process at the call")
	local found, err = signal.kill(pids.reaped, sig.TERM)
	assert(found == nil and err == "ESRCH",
		"a reaped pid should answer nil and ESRCH at the call, got " .. tostring(found) .. ", " .. tostring(err))
end

return kill

