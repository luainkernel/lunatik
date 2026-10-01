--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fifo push test (see run.sh).

local fifo = require("fifo")
local test = require("tests.lib").test

local pack   = table.pack
local rep    = string.rep
local format = string.format

local CAPACITY <const> = 16
local HALF     <const> = rep("x", CAPACITY // 2)
local OVER     <const> = HALF .. "y" -- a byte past the room a pushed HALF leaves

local function answers(expected, queue, data)
	local answer = pack(queue:push(data))
	assert(answer.n == 1 and answer[1] == expected,
		format("push of %d bytes answered %d values, the first %s", #data, answer.n, tostring(answer[1])))
end

test("fifo:push answers true while the fifo has room for the bytes", function()
	local queue <close> = fifo.new(CAPACITY)
	answers(true, queue, HALF)
	answers(true, queue, HALF)
	assert(queue:pop(CAPACITY) == HALF .. HALF, "the fifo lost a push")
end)

test("fifo:push answers false and takes nothing when the fifo has no room for all of them", function()
	local queue <close> = fifo.new(CAPACITY)
	answers(true, queue, HALF)
	answers(false, queue, OVER)
	assert(queue:pop(CAPACITY) == HALF, "a refused push left bytes behind")
	answers(true, queue, OVER)
end)

