--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the darken context test (see run.sh).

local lunatik = require("lunatik")
local test    = require("util").test

local RECEIVER <const> = "tests/darken/context_recv"
local REFUSAL  <const> = "not allowed once the runtime is armed"

local function resume(context)
	local runtime <close> = lunatik.runtime(RECEIVER, context)
	return pcall(runtime.resume, runtime)
end

local function refused(context)
	local ok, err = resume(context)
	assert(not ok, "an armed " .. context .. " runtime ran darken")
	assert(err:match(REFUSAL), "an armed " .. context .. " runtime raised something else: " .. err)
end

test("darken.run runs in a process runtime past its body", function()
	local ok, err = resume("process")
	assert(ok, err)
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("darken.run refuses an armed softirq runtime", function()
	refused("softirq")
end)

test("darken.run refuses an armed hardirq runtime", function()
	refused("hardirq")
end)

