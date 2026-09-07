--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the resume_results test (see resume_results.sh);
-- yields, and finally returns, what the driver expects to get back.

local data = require("data")

local ANSWER <const> = 42
local FIRST <const> = 1
local SECOND <const> = 2
local MANY <const> = 32

local function byte(value)
	local d = data.new(1)
	d:setbyte(0, value)
	return d
end

local function recv(first, second)
	assert(#first == FIRST and #second == SECOND, "resume did not deliver its arguments in order")
	coroutine.yield(byte(ANSWER))
	local many = table.pack(coroutine.yield(byte(FIRST), byte(SECOND)))
	assert(many.n == MANY, "resume delivered " .. many.n .. " of the " .. MANY .. " objects it was given")
	coroutine.yield(table.unpack(many, 1, many.n))
	coroutine.yield(ANSWER)
	coroutine.yield(data.new(4, "single"))
	return byte(ANSWER)
end

return recv

