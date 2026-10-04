--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.schedule test (see run.sh).
--

local linux   = require("linux")
local lunatik = require("lunatik")
local test    = require("tests.lib").test

local NAP_MS   <const> = 1
local RECEIVER <const> = "tests/linux/schedule_recv"

-- past msecs_to_jiffies's unsigned int, which a build without the bound naps on, before two it reads as forever
local refused <const> = {(1 << 32) | NAP_MS, -1, 1 << 31}

test("linux.schedule sleeps and returns the time left in a process runtime", function()
	local left = linux.schedule(NAP_MS)
	assert(left == 0, "expected the whole nap, " .. tostring(left) .. " ms left")
end)

test("linux.schedule refuses a timeout outside 0 to 2^31 - 1, and takes 0", function()
	for _, timeout in ipairs(refused) do
		local ok, err = pcall(linux.schedule, timeout)
		assert(not ok and err:find("out of bounds", 1, true),
			"linux.schedule(" .. timeout .. ") answered " .. tostring(err))
	end
	assert(linux.schedule(0) == 0, "linux.schedule(0) left time")
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

