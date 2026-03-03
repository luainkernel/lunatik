--
-- SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Network utility functions.
-- This module provides helper functions for network-related operations,
-- primarily for converting between string and integer representations of IPv4 addresses.
-- @module net
--

local net = {}

---
-- Converts an IPv4 address string to its integer representation.
-- "Address to Number"
-- @param addr (string) The IPv4 address string (e.g., "127.0.0.1").
-- @return (number) The IPv4 address as an integer.
-- @usage
--   local ip_int = net.aton("192.168.1.1")
function net.aton(addr)
	local i = 1
	local bits = { 24, 16, 8, 0 }
	local ip = 0
	for n in string.gmatch(addr, "(%d+)") do
		local n = tonumber(n) & 0xFF
		ip = ip | (n << bits[i])
		i = i + 1
	end
	return ip
end

---
-- Converts an integer representation of an IPv4 address to its string form.
-- "Number to Address"
-- @param ip (number) The IPv4 address as an integer.
-- @return (string) The IPv4 address string (e.g., "127.0.0.1").
-- @usage
--   local ip_str = net.ntoa(3232235777)  -- "192.168.1.1"
function net.ntoa(ip)
	local n = 4
	local bytes = {}
	for i = 1, n do
		local shift = (n - i) * 8
		local mask = 0xFF << shift
		bytes[i] = (ip & mask) >> shift
	end
	return table.concat(bytes, ".")
end

return net

