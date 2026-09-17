-- see packet.sh and bounds.sh: the packets every differential case runs over, written as hex so
-- that the headers stay readable, and handed to both sides as the same bytes.

local gsub, char = string.gsub, string.char

local packets = {}

local function byte(pair)
	return char(tonumber(pair, 16))
end

local function bytes(hex)
	return (gsub(gsub(hex, "%s+", ""), "%x%x", byte))
end

--- The corpus, in the order the cases run it.
packets.order = {"arp", "icmp", "syn", "tls", "truncated"}

-- every frame carries the same source address, whose first byte has its high bit set, so the
-- signed accessors have something to sign-extend on every packet of the corpus
packets.arp = bytes[[
	ffffffffffff f0eeddccbbaa 0806
	0001 0800 06 04 0001 f0eeddccbbaa c0a80101 000000000000 c0a80102
]]

packets.icmp = bytes[[
	001122334455 f0eeddccbbaa 0800
	45 00 001c 0001 0000 40 01 0000 0a000001 0a000002
	08 00 f7ff 0001 0001
]]

packets.syn = bytes[[
	001122334455 f0eeddccbbaa 0800
	45 00 002c 0002 4000 40 06 0000 0a000001 0a000002
	c0de 01bb 11223344 00000000 6002 ffff 0000 0000 020405b4
]]

-- a ClientHello whose SNI names example.com, the packet the SNI filter is written for
packets.tls = bytes[[
	001122334455 f0eeddccbbaa 0800
	45 00 0070 0003 4000 40 06 0000 0a000001 0a000002
	c0de 01bb 11223345 22334455 5018 ffff 0000 0000
	16 0301 0043
	01 00003f 0303
	a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4
	00 0002 1301 01 00
	0014 0000 0010 000e 00 000b 6578616d706c652e636f6d
]]

-- the same ClientHello cut after its record header, so a read that lands in the SNI of the whole
-- one is out of bounds here
packets.truncated = packets.tls:sub(1, 60)

return packets

