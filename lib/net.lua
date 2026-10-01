--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Network utility functions.
-- This module provides helper functions for network-related operations,
-- primarily for converting between string and integer representations of IPv4 addresses.
-- @module net
--

local gmatch = string.gmatch

local net = {}

---
-- Converts an IPv4 address string to its integer representation.
-- "Address to Number"
-- @param addr (string) The IPv4 address string, four decimal octets from 0 to 255 joined by dots,
--   with no leading zero (e.g., "127.0.0.1").
-- @return (number) The IPv4 address as an integer.
-- @raise "invalid IPv4 address" for any other string.
-- @usage
--   local ip_int = net.aton("192.168.1.1")
function net.aton(addr)
	local ip = 0
	for octet in gmatch(addr, "%d%d?%d?") do
		ip = (ip << 8) | tonumber(octet)
	end
	-- ntoa spells every address one way, four octets from 0 to 255 with no leading zero
	if net.ntoa(ip) ~= addr then
		error("invalid IPv4 address: " .. addr, 2)
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

