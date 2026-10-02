--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/patterns test (see run.sh).
--

local test = require("tests.lib").test

local rep, match = string.rep, string.match

local MATCHDEPTH <const> = 32
local CAPTURES <const> = MATCHDEPTH // 2 - 1
local REFUSAL <const> = "pattern too complex"
local OPTIONAL <const> = "a?"
local CAPTURE <const> = "(a)"

local subject = rep("a", MATCHDEPTH)

local operations <const> = {find = string.find, match = match}

function operations.gmatch(s, pattern)
	return s:gmatch(pattern)()
end

function operations.gsub(s, pattern)
	return s:gsub(pattern, "")
end

local function refused(operation, pattern)
	local ok, err = pcall(operation, subject, pattern)
	return not ok and err:find(REFUSAL, 1, true) ~= nil, err
end

test("an optional item per level up to the bound matches in find, match, gmatch and gsub", function()
	local pattern = rep(OPTIONAL, MATCHDEPTH - 1)
	for name, operation in pairs(operations) do
		local ok, result = pcall(operation, subject, pattern)
		assert(ok and result ~= nil, name .. " did not match: " .. tostring(result))
	end
end)

test("one optional item past the bound raises 'pattern too complex' in each of them", function()
	local pattern = rep(OPTIONAL, MATCHDEPTH)
	for name, operation in pairs(operations) do
		local refusal, err = refused(operation, pattern)
		assert(refusal, name .. " was not refused: " .. tostring(err))
	end
end)

test("a capture takes two levels", function()
	local fits = rep(CAPTURE, CAPTURES) .. OPTIONAL
	assert(select("#", match(subject, fits)) == CAPTURES, "the captures up to the bound did not match")
	local refusal, err = refused(match, rep(CAPTURE, CAPTURES + 1))
	assert(refusal, "a capture past the bound was not refused: " .. tostring(err))
end)

