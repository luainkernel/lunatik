-- see packet.sh and bounds.sh: the packets every differential case runs over, written as hex so
-- that the headers stay readable, and handed to both sides as the same bytes.

local gsub, char, pack = string.gsub, string.char, string.pack

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

-- The pieces of the ClientHello above that a host name does not move, so a frame naming another
-- one reaches the same offsets: the builder is beside the literal rather than under it, since
-- rebuilding the corpus from it would move every figure the earlier phases recorded.
local ETHERNET <const> = bytes[[001122334455 f0eeddccbbaa 0800]]
local IPV4     <const> = bytes[[45 00]]
local IPTAIL   <const> = bytes[[0003 4000 40 06 0000 0a000001 0a000002]]
local IPHDR    <const> = 20
local TCPHDR   <const> = bytes[[c0de 01bb 11223345 22334455 5018 ffff 0000 0000]]
local RECORD   <const> = bytes[[16 0301]] -- a handshake record, TLS 1.0 on the wire
local HELLO    <const> = bytes[[01]]
local VERSION  <const> = bytes[[0303]]
local RANDOM   <const> = bytes[[a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4 a1b2c3d4]]
local NOSESSION <const> = bytes[[00]]
local SUITES   <const> = bytes[[0002 1301]]
local COMPRESS <const> = bytes[[01 00]]
local SERVERNAME <const> = bytes[[0000]] -- the extension type the parser looks for
local HOSTNAME <const> = bytes[[00]]     -- and the one name type its list carries

--- A ClientHello frame naming `host`, with every length the parser walks computed from it.
-- @tparam string host the server name the extension carries
-- @treturn string the whole ethernet frame
function packets.clienthello(host)
	local name = HOSTNAME .. pack(">I2", #host) .. host
	local list = pack(">I2", #name) .. name
	local extension = SERVERNAME .. pack(">I2", #list) .. list
	local hello = VERSION .. RANDOM .. NOSESSION .. SUITES .. COMPRESS
		.. pack(">I2", #extension) .. extension
	local handshake = HELLO .. pack(">I3", #hello) .. hello
	local payload = RECORD .. pack(">I2", #handshake) .. handshake
	return ETHERNET .. IPV4 .. pack(">I2", IPHDR + #TCPHDR + #payload) .. IPTAIL .. TCPHDR .. payload
end

return packets

