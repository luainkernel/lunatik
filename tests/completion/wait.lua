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

-- past msecs_to_jiffies's unsigned int, which a build without the bound waits on, before two it reads as forever
local refused <const> = {(1 << 32) | TIMEOUT, -1, 1 << 31}

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

test("completion:wait refuses a timeout outside 0 to 2^31 - 1", function()
	local event = completion.new()
	for _, timeout in ipairs(refused) do
		local ok, err = pcall(event.wait, event, timeout)
		assert(not ok and err:find("out of bounds", 1, true), format("wait(%d) answered %s", timeout, tostring(err)))
	end
end)

test("completion:wait answers false when the timeout elapses first", function()
	local event = completion.new()
	answers(false, event, TIMEOUT)
	answers(false, event, 0)
end)

