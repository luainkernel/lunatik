--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.signal test (see run.sh).
--

local signal = require("linux.signal")
local test   = require("tests.lib").test
local check  = require("tests.linux.check")

-- the how of sigprocmask (SIG_BLOCK), the sigevent notifications (SIGEV_*) and the stack size (SIGSTKSZ)
local others = { "^_", "^EV_", "^STKSZ$" }

test("linux.signal carries the signals and no other name under SIG", function()
	check.carries("signal", signal, { HUP = 1, KILL = 9, TERM = 15 })
	for key in pairs(signal) do
		for _, other in ipairs(others) do
			assert(not key:match(other), ("linux.signal.%s is not a signal"):format(key))
		end
	end
end)

