--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the struct case (see struct.sh).

local corpus  = require("tests.luaebpf.corpus")
local map     = require("bpf.map")
local struct  = require("struct")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local pack, bytes    = string.pack, corpus.bytes
local insert, sort = table.insert, table.sort

local KEY     <const> = "I4"
local AT      <const> = 1
local MISS    <const> = 9

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

local function u8(_) local v = records[AT] if v then return v.u8 end return MISS end
local function i8(_) local v = records[AT] if v then return v.i8 end return MISS end
local function u16(_) local v = records[AT] if v then return v.u16 end return MISS end
local function i16(_) local v = records[AT] if v then return v.i16 end return MISS end
local function u32(_) local v = records[AT] if v then return v.u32 end return MISS end
local function i32(_) local v = records[AT] if v then return v.i32 end return MISS end
local function ttl(_) local v = headers[AT] if v then return v.ttl end return MISS end
local function protocol(_) local v = headers[AT] if v then return v.protocol end return MISS end
local function totlen(_) local v = headers[AT] if v then return v.tot_len end return MISS end

local reads = {{"u8", u8}, {"i8", i8}, {"u16", u16}, {"i16", i16}, {"u32", u32}, {"i32", i32},
	{"ttl", ttl}, {"protocol", protocol}, {"totlen", totlen}}
for _, read in ipairs(reads) do
	corpus.program(xdp.program, {name = read[1]}, corpus.returning, read[2])
end
corpus.close()

corpus.frame()

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
	out:write("expect\t", value[1], "\t", value[2], "\n")
end
out:write("expect\tttl\t", header_fields.ttl, "\n")
out:write("expect\tprotocol\t", header_fields.protocol, "\n")
out:write("expect\ttotlen\t", header_fields.tot_len, "\n")
out:close()

