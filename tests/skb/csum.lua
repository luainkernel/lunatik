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

-- data:checksum complements the folded sum; the pseudo-header's alone is what the stack or the device completes
function csum.seed(data, addrs, addrslen, offset, proto)
	return fold((ONES - data:checksum(addrs, addrslen)) + byteorder.hton16(proto) + byteorder.hton16(#data - offset))
end

-- a segment and its pseudo-header that verify fold to ONES
function csum.sum(data, addrs, addrslen, offset, proto)
	return fold(csum.seed(data, addrs, addrslen, offset, proto) + (ONES - data:checksum(offset, #data - offset)))
end

function csum.summed(data, addrs, addrslen, offset, proto)
	return csum.sum(data, addrs, addrslen, offset, proto) == ONES
end

return csum

