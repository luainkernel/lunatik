-- see struct.sh
local corpus  = require("tests.luaebpf.corpus")
local map     = require("bpf.map")
local struct  = require("struct")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local pack, insert, concat, sort = string.pack, table.insert, table.concat, table.sort

local KEY     <const> = "I4"
local AT      <const> = 1
local MISS    <const> = 9
local WORD    <const> = 0xffffffff
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

-- one field of every width and signedness, with a gap the codec reads as padding
local record = struct{size = 16, fields = {
	{name = "u8", offset = 0, size = 1, signed = false},
	{name = "i8", offset = 1, size = 1, signed = true},
	{name = "u16", offset = 2, size = 2, signed = false},
	{name = "i16", offset = 4, size = 2, signed = true},
	{name = "u32", offset = 8, size = 4, signed = false},
	{name = "i32", offset = 12, size = 4, signed = true},
}}

-- the kernel's own IPv4 header, at the offsets its BTF reports, which ties the reader to the
-- map path: a field the emitter reads at a wrong offset answers a different byte here
local header = struct(vmlinux.layout("iphdr"))

local records = map.hash("records", {key = KEY, value = record, entries = 8})
local headers = map.hash("headers", {key = KEY, value = header, entries = 8})

local function u8(ctx) local v = records[AT] if v then return v.u8 end return MISS end
local function i8(ctx) local v = records[AT] if v then return v.i8 end return MISS end
local function u16(ctx) local v = records[AT] if v then return v.u16 end return MISS end
local function i16(ctx) local v = records[AT] if v then return v.i16 end return MISS end
local function u32(ctx) local v = records[AT] if v then return v.u32 end return MISS end
local function i32(ctx) local v = records[AT] if v then return v.i32 end return MISS end
local function ttl(ctx) local v = headers[AT] if v then return v.ttl end return MISS end
local function protocol(ctx) local v = headers[AT] if v then return v.protocol end return MISS end
local function totlen(ctx) local v = headers[AT] if v then return v.tot_len end return MISS end

local reads = {{"u8", u8}, {"i8", i8}, {"u16", u16}, {"i16", i16}, {"u32", u32}, {"i32", i32},
	{"ttl", ttl}, {"protocol", protocol}, {"totlen", totlen}}
for _, read in ipairs(reads) do
	xdp.program(read[2], {name = read[1]})
end

corpus.context("frame", "xdp_md", {ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)

local function bytes(packed)
	local out = {}
	for i = 1, #packed do
		insert(out, tostring(packed:byte(i)))
	end
	return concat(out, " ")
end

local function byoffset(a, b)
	return a.offset < b.offset
end

-- a codec unpacks its fields in offset order, which is the order the case reads them back in
local function decode(codec, raw)
	local order, values, decoded = {}, {}, {codec:unpack(raw)}
	for _, field in ipairs(codec.layout.fields) do
		insert(order, field)
	end
	sort(order, byoffset)
	for i, field in ipairs(order) do
		values[field.name] = decoded[i]
	end
	return values
end

local values = {{"u8", 0xf0}, {"i8", -16}, {"u16", 0xfedc}, {"i16", -300}, {"u32", 0xdeadbeef},
	{"i32", -1000}}
local packed = record:pack(values[1][2], values[2][2], values[3][2], values[4][2], values[5][2],
	values[6][2])
-- an IPv4 header the shell could have captured: version and IHL, a total length, an id, flags,
-- a TTL and a protocol, then the addresses
local wire <const> = "\x45\x00\x00\x1c\x00\x01\x00\x00\x40\x01\x00\x00\x0a\x00\x00\x01\x0a\x00\x00\x02"
local header_fields = decode(header, wire)

local out = assert(io.open("rows.txt", "w"))
out:write("seed\trecords\t", bytes(pack(KEY, AT)), "\t", bytes(packed), "\n")
out:write("seed\theaders\t", bytes(pack(KEY, AT)), "\t", bytes(wire), "\n")
for _, value in ipairs(values) do
	out:write("expect\t", value[1], "\t", value[2] & WORD, "\n")
end
out:write("expect\tttl\t", header_fields.ttl & WORD, "\n")
out:write("expect\tprotocol\t", header_fields.protocol & WORD, "\n")
out:write("expect\ttotlen\t", header_fields.tot_len & WORD, "\n")
out:close()

