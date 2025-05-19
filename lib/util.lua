--- Utility functions.
--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- @module util

local format, rep, sp, su = string.format, string.rep, string.pack, string.unpack
local concat, remove, sort = table.concat, table.remove, table.sort

--- Converts a binary string to its hexadecimal representation.
-- @tparam string str The binary string to convert.
-- @treturn string A string containing the hexadecimal representation of the input.
local function bin2hex(str)
	return format(
		rep("%.2x", #str),
		su(rep("B", #str), str)
	)
end

--- Converts a hexadecimal string to its binary representation.
-- @tparam string hex The hexadecimal string to convert.
-- @treturn string A string containing the binary representation of the input.
local function hex2bin(hex)
	local bytes = { su(rep("c2", #hex / 2), hex) }
	remove(bytes)  -- string.unpack returns extra value at the end
	for i = 1, #bytes do
		bytes[i] = sp("B", tonumber(bytes[i], 16))
	end
	return concat(bytes)
end

--- Returns an iterator that traverses a table in sorted key order.
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
