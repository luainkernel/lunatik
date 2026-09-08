--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fifo bounds test (see run.sh).

local fifo = require("fifo")
local test = require("util").test

local CAPACITY <const> = 16
local MESSAGE  <const> = "hello"

local accepted   <const> = {2, 16, 4096, 1 << 20}
-- fifo.new tops out at KMALLOC_MAX_SIZE, which follows the kernel's page size and MAX_PAGE_ORDER;
-- 2^32 is past it on every configuration.
local refused    <const> = {1, 0, -1, (1 << 32) + 8, math.maxinteger, math.mininteger}
local unpoppable <const> = {-1, CAPACITY + 1, math.maxinteger, math.mininteger}

local function refuses(what, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " accepted a size it cannot serve")
	assert(err:match("out of bounds"), what .. " raised something else: " .. err)
end

test("fifo.new accepts a size it serves", function()
	for _, size in ipairs(accepted) do
		local queue <close> = fifo.new(size)
		local message = MESSAGE:sub(1, size)
		queue:push(message)
		assert(queue:pop(#message) == message, "the fifo of " .. size .. " bytes lost the message")
	end
end)

test("fifo.new refuses a size it cannot serve", function()
	for _, size in ipairs(refused) do
		refuses("fifo.new", fifo.new, size)
	end
end)

test("fifo:pop accepts a size up to the capacity", function()
	local queue <close> = fifo.new(CAPACITY)
	assert(queue:pop(0) == "", "an empty pop returned bytes")
	queue:push(MESSAGE)
	assert(queue:pop(CAPACITY) == MESSAGE, "a capacity-sized pop lost the message")
end)

test("fifo:pop refuses a size past the capacity", function()
	local queue <close> = fifo.new(CAPACITY)
	local pop = getmetatable(queue).pop
	for _, size in ipairs(unpoppable) do
		refuses("fifo:pop", pop, queue, size)
	end
end)

