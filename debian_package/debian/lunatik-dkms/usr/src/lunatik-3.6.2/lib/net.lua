--
-- SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local net = {}

function net.aton(addr)
	local i = 1
	local bits = { 24, 16, 8, 0 }
	local ip = 0
	for n in string.gmatch(addr, "(%d+)") do
		n = tonumber(n) & 0xFF
		ip = ip | (n << bits[i])
		i = i + 1
	end
	return ip
end

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

