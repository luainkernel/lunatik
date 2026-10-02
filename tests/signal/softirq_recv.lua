--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Receiver sub-script for signal/softirq (see run.sh).

local signal = require("signal")

local INIT <const> = 1

local function kill()
	assert(signal.kill(INIT, 0) == true, "kill(1, 0) should answer in a softirq runtime's callback, with IRQs on")
end

return kill

