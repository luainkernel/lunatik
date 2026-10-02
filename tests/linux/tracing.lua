--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.tracing test (see run.sh).
--

local linux   = require("linux")
local lunatik = require("lunatik")
local test    = require("tests.lib").test

local RECEIVER <const> = "tests/linux/tracing_recv"

local contexts <const> = {"process", "softirq", "hardirq"}
local refused  <const> = {0, 1, "on", {}}

local found = linux.tracing()

test("linux.tracing reads the state when given nothing or nil", function()
	linux.tracing(true)
	assert(linux.tracing() == true and linux.tracing(nil) == true, "a read turned tracing off")
	linux.tracing(false)
	assert(linux.tracing() == false and linux.tracing(nil) == false, "a read turned tracing on")
end)

test("linux.tracing refuses a value that is neither a boolean nor nil, and changes nothing", function()
	for _, value in ipairs(refused) do
		local ok, err = pcall(linux.tracing, value)
		assert(not ok and err:match("boolean expected"), "tracing(" .. tostring(value) .. ") was not refused")
	end
	assert(linux.tracing() == false, "a refused value turned tracing on")
end)

-- a runtime is armed past its body, which is the state a hook calls from; resume reaches it
for _, context in ipairs(contexts) do
	test("linux.tracing turns tracing off and on from an armed " .. context .. " runtime", function()
		local runtime <close> = lunatik.runtime(RECEIVER, context)
		runtime:resume()
	end)
end

linux.tracing(found)

