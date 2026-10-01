--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Utility functions.
-- `bin2hex` and `hex2bin` convert between a binary string and its hexadecimal representation.
-- @module util

local util = {}
local byte, char, format, gsub = string.byte, string.char, string.format, string.gsub

local function tohex(c)
	return format("%.2x", byte(c))
end

--- Converts a binary string to its hexadecimal representation.
-- @function bin2hex
-- @tparam string str binary string to convert.
-- @treturn string hexadecimal representation of the input, two lowercase digits per byte.
function util.bin2hex(str)
	return (gsub(str, ".", tohex))
end

--- Converts a hexadecimal string to its binary representation.
-- @function hex2bin
-- @tparam string hex hexadecimal string to convert.
-- @treturn string binary representation of the input.
function util.hex2bin(hex)
	return gsub(hex, "..", function(cc) return char(tonumber(cc, 16)) end)
end

return util

