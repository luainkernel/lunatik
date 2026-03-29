--- IPv4 utility functions.
-- @module net

local net = {}

--- Converts IPv4 address string to integer.
-- @tparam string addr IPv4 address (e.g., "127.0.0.1").
-- @treturn number IPv4 address as integer.
-- @usage local ip = net.aton("192.168.1.1")
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

--- Converts IPv4 integer to address string.
-- @tparam number ip IPv4 address as integer.
-- @treturn string IPv4 address string.
-- @usage local addr = net.ntoa(3232235777)
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

