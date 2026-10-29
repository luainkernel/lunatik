--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The native crypto.comp's class check (see run.sh).

local comp = require("crypto").comp
local data = require("data")
local lib = require("tests.lib")
local test = lib.test

lib.alloc(comp, "lz4")

test("COMP refuses an object of another class, naming crypto.comp", function()
	local c = comp"lz4"
	local status, err = pcall(c.compress, data.new(8), "x", 16)
	assert(not status, "compress accepted an object of another class")
	assert(err:find("crypto.comp expected, got data", 1, true), "compress raised something else: " .. err)
end)

