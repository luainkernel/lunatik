--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.schedule test (see run.sh).
--

local linux   = require("linux")
local lunatik = require("lunatik")
local test    = require("util").test

local NAP_MS   <const> = 1
local RECEIVER <const> = "tests/linux/schedule_recv"

test("linux.schedule sleeps and returns the time left in a process runtime", function()
	local left = linux.schedule(NAP_MS)
	assert(left == 0, "expected the whole nap, " .. tostring(left) .. " ms left")
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("linux.schedule refuses an armed softirq runtime", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
	runtime:resume()
end)

test("linux.schedule refuses an armed hardirq runtime", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "hardirq")
	runtime:resume()
end)

