--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the completion wait test (see run.sh).

local completion = require("completion")
local test       = require("tests.lib").test

local pack   = table.pack
local format = string.format

local TIMEOUT <const> = 10 -- ms

local function answers(expected, event, timeout)
	local answer = pack(event:wait(timeout))
	assert(answer.n == 1 and answer[1] == expected,
		format("wait(%d) answered %d values, the first %s", timeout, answer.n, tostring(answer[1])))
end

test("completion:wait answers true for a completion signaled before it", function()
	local event = completion.new()
	event:complete()
	answers(true, event, TIMEOUT)
	event:complete()
	answers(true, event, 0)
end)

test("completion:wait answers false when the timeout elapses first", function()
	local event = completion.new()
	answers(false, event, TIMEOUT)
	answers(false, event, 0)
end)

