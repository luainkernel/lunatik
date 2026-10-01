--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Utility functions.
-- `bin2hex` and `hex2bin` convert between a binary string and its hexadecimal representation.
-- @module util

local util = {}
local byte, char, find, format, gsub = string.byte, string.char, string.find, string.format, string.gsub

local function tohex(c)
	return format("%.2x", byte(c))
end

local function tochar(cc)
	return char(tonumber(cc, 16))
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
-- @tparam string hex hexadecimal string to convert, two digits per byte in either case.
-- @treturn string binary representation of the input.
-- @raise `"invalid hexadecimal string"` when `hex` has an odd length or a character that is not a hexadecimal digit.
function util.hex2bin(hex)
	if #hex % 2 ~= 0 or find(hex, "%X") then
		error("invalid hexadecimal string", 2)
	end
	return (gsub(hex, "..", tochar))
end

return util

