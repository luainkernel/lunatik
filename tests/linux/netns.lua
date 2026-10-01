--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.netns test (see run.sh).
--

local lunatik = require("lunatik")
local test    = require("util").test

local RECEIVER <const> = "tests/linux/netns_recv"
local REFUSAL  <const> = "not allowed once the runtime is armed"

local function resume(context)
	local runtime <close> = lunatik.runtime(RECEIVER, context)
	return pcall(runtime.resume, runtime)
end

local function refused(context)
	local ok, err = resume(context)
	assert(not ok, "an armed " .. context .. " runtime resolved a pid")
	assert(err:match(REFUSAL), "an armed " .. context .. " runtime raised something else: " .. err)
end

test("linux.netns resolves a pid in a process runtime past its body", function()
	local ok, err = resume("process")
	assert(ok, err)
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("linux.netns refuses a pid in an armed softirq runtime", function()
	refused("softirq")
end)

test("linux.netns refuses a pid in an armed hardirq runtime", function()
	refused("hardirq")
end)

