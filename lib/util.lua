--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Utility functions.
-- @module util

local char, format, gsub, rep, su = string.char, string.format, string.gsub, string.rep, string.unpack
local sort = table.sort

--- Converts a binary string to its hexadecimal representation.
-- @function bin2hex
-- @tparam string str The binary string to convert.
-- @treturn string A string containing the hexadecimal representation of the input.
local function bin2hex(str)
	return format(rep("%.2x", #str), su(rep("B", #str), str))
end

--- Converts a hexadecimal string to its binary representation.
-- @function hex2bin
-- @tparam string hex The hexadecimal string to convert.
-- @treturn string A string containing the binary representation of the input.
local function hex2bin(hex)
  return gsub(hex, "%x%x", function(cc) return char(tonumber(cc, 16)) end)
end

--- Returns an iterator that traverses a table in sorted key order.
-- @function opairs
-- @tparam table tbl The table to iterate over.
-- @tparam[opt] function fn A comparison function to sort the keys.
-- @treturn function An iterator function that, when called, returns the next key (`any`) and value (`any`) in sorted order, or `nil` once iteration is complete.
local function opairs(tbl, fn)
	local i, keys = 1, {}
	for k in pairs(tbl) do
		keys[i] = k
		i = i + 1
	end
	sort(keys, fn)
	i = 1
	local k
	return function()
		k = keys[i]
		i = i+1
		return k, tbl[k]
	end
end

return {
	bin2hex = bin2hex,
	hex2bin = hex2bin,
	opairs = opairs,
}
