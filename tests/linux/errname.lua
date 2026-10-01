--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.errname test (see run.sh).
--

local linux = require("linux")
local test  = require("util").test

local ENOENT      <const> = 2
local INT_MAX     <const> = 0x7FFFFFFF
local INT_MIN     <const> = -0x80000000
local OUTOFBOUNDS <const> = "out of bounds"

local names <const> = {
	[ENOENT]   = "ENOENT",
	[-ENOENT]  = "ENOENT",
	[INT_MAX]  = "unknown",
	[-INT_MAX] = "unknown",
}

local refused <const> = {INT_MIN, INT_MAX + 1, (1 << 32) | ENOENT}

test("linux.errname names an errno of either sign and answers unknown for the ends of an int", function()
	for err, name in pairs(names) do
		local got = linux.errname(err)
		assert(got == name, ("errname(%d) is %s, expected %s"):format(err, got, name))
	end
end)

test("linux.errname refuses a number past an int, and INT_MIN, which has no absolute value", function()
	for _, err in ipairs(refused) do
		local ok, msg = pcall(linux.errname, err)
		assert(not ok, ("errname(%d) answered %s"):format(err, tostring(msg)))
		assert(msg:find(OUTOFBOUNDS, 1, true), ("errname(%d) raised something else: %s"):format(err, msg))
	end
end)

