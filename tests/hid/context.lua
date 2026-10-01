--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the hid context test (see context.sh).

local lunatik = require("lunatik")
local test    = require("tests.lib").test

local RECEIVER <const> = "tests/hid/context_recv"
local REFUSAL  <const> = "not allowed once the runtime is armed"

-- a softirq runtime is armed past its body, which is the state a callback runs in; resume reaches it
test("hid.register refuses an armed softirq runtime", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
	local ok, err = pcall(runtime.resume, runtime)
	assert(not ok, "an armed softirq runtime registered a driver")
	assert(err:match(REFUSAL), "an armed softirq runtime raised something else: " .. err)
end)

