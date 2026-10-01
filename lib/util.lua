--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Utility functions.
-- `bin2hex` and `hex2bin` convert binary strings.
-- @module util

local util = {}
local char, format, gsub, rep, su = string.char, string.format, string.gsub, string.rep, string.unpack

--- Converts a binary string to its hexadecimal representation.
-- @function bin2hex
-- @tparam string str binary string to convert.
-- @treturn string hexadecimal representation of the input.
function util.bin2hex(str)
	return format(rep("%.2x", #str), su(rep("B", #str), str))
end

--- Converts a hexadecimal string to its binary representation.
-- @function hex2bin
-- @tparam string hex hexadecimal string to convert.
-- @treturn string binary representation of the input.
function util.hex2bin(hex)
	return gsub(hex, "..", function(cc) return char(tonumber(cc, 16)) end)
end

return util

