--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/util test (see run.sh).
--

local util = require("util")
local test = require("tests.lib").test

local char, format, rep = string.char, string.format, string.rep
local concat, insert, pack = table.concat, table.insert, table.pack

local COPIES <const> = 8 -- of every byte value: 2048 bytes, past the 200 slots of LUAI_MAXSTACK (lunatik_conf.h)

local bytes, digits = {}, {}
for value = 0, 255 do
	insert(bytes, char(value))
	insert(digits, format("%.2x", value))
end
local binary, hexadecimal = rep(concat(bytes), COPIES), rep(concat(digits), COPIES)

test("util.bin2hex encodes every byte value, in a string longer than the stack", function()
	local encoded = pack(util.bin2hex(binary))
	assert(encoded[1] == hexadecimal, "bin2hex did not encode every byte value")
	assert(encoded.n == 1, "bin2hex returned more than the string")
	assert(util.bin2hex("") == "", "bin2hex did not encode the empty string")
end)

