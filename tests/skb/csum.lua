--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The Internet checksum the skb:checksum() cases verify against (see checksum.sh and tests/tc/test_tc.sh).

local byteorder = require("byteorder")

local ONES <const> = 0xffff

local csum = {}

local function fold(sum)
	while sum > ONES do
		sum = (sum & ONES) + (sum >> 16)
	end
	return sum
end

-- data:checksum complements the folded sum; a segment and its pseudo-header that verify fold to ONES
function csum.sum(data, addrs, addrslen, offset, proto)
	local len = #data - offset
	return fold((ONES - data:checksum(addrs, addrslen)) + (ONES - data:checksum(offset, len)) +
		byteorder.hton16(proto) + byteorder.hton16(len))
end

function csum.summed(data, addrs, addrslen, offset, proto)
	return csum.sum(data, addrs, addrslen, offset, proto) == ONES
end

return csum

