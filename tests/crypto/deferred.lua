--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto deferred test (see deferred.sh).

local comp = require("crypto").comp
local test = require("tests.lib").test

local rep = string.rep

local ALGORITHM <const> = "lunatik-deferred"
local DATA <const> = rep("deferred", 64)
local MAX_LEN <const> = 2 * #DATA -- past the input, so a length read before the wait is not the output's

local function whole(output)
	assert(output == DATA, "returned " .. #output .. " bytes other than the input's " .. #DATA)
end

local function short(c, method)
	local status, err = pcall(method, c, DATA, #DATA - 1)
	assert(not status and err == "EINVAL", "an output shorter than the input raised " .. tostring(err))
end

test("COMP algname of an asynchronous implementation", function()
	local name = comp(ALGORITHM):algname()
	assert(name == ALGORITHM, "algname should be '" .. ALGORITHM .. "', got: " .. name)
end)

test("COMP compress waits for the completion that writes the output", function()
	local c = comp(ALGORITHM)
	whole(c:compress(DATA, MAX_LEN))
end)

test("COMP decompress waits for a backlogged request", function()
	local c = comp(ALGORITHM)
	whole(c:decompress(DATA, MAX_LEN))
end)

test("COMP compress raises the EINVAL its completion carries", function()
	local c = comp(ALGORITHM)
	short(c, c.compress)
end)

test("COMP decompress raises the EINVAL a backlogged completion carries", function()
	local c = comp(ALGORITHM)
	short(c, c.decompress)
end)

