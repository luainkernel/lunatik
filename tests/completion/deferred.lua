--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the completion deferred test (see run.sh).

local lunatik    = require("lunatik")
local completion = require("completion")
local test       = require("tests.lib").test

local COMPLETER <const> = "tests/completion/complete"
local IRQSOFF   <const> = "hardirq"
local DEFERRED  <const> = 1000 -- ms, for the kernel worker to wake the waiter

local function completes(event, context, timeout)
	local completer <close> = lunatik.runtime(COMPLETER, context)
	completer:resume(event)
	assert(event:wait(timeout) and event:wait(timeout), "a complete of the " .. context .. " callback was lost")
	assert(not event:wait(0), "the " .. context .. " callback's two completes woke the waiter a third time")
end

test("completion:complete with IRQs off wakes the waiter once per call, after the callback", function()
	local event = completion.new()
	completes(event, IRQSOFF, DEFERRED)
	completes(event, IRQSOFF, DEFERRED)
end)

test("completion:complete with IRQs on wakes the waiter in place", function()
	completes(completion.new(), "softirq", 0)
end)

