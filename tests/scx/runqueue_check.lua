--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script that reads the scx runqueue test's record (see run.sh).

local lunatik = require("lunatik")
local test    = require("tests.lib").test

local KEY <const> = "scx runqueue"

local env    = lunatik._ENV
local record = env[KEY]
env[KEY] = nil

local function reached(step)
	assert(record ~= nil, "runqueue.lua left no record")
	local value = record[step]
	assert(value ~= nil, "the callback did not reach " .. step)
	return value
end

test("written", function()
	reached("written")
end)

test("refused", function()
	assert(reached("complete"), "complete was not refused")
	assert(reached("send"), "send was not refused")
	assert(reached("queued"), "send did not leave its message queued")
end)

test("raised", function()
	reached("raised")
	reached("decided")
end)

test("freed", function()
	assert(reached("moved"), "a buffer the allocator moved lost its bytes")
	reached("freed")
end)

test("detached", function()
	reached("detached")
end)

