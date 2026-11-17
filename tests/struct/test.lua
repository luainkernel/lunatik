--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the struct test (see run.sh).

local struct = require("struct")

-- a layout exercising an inter-field padding gap, a signed field and a
-- trailing pad (the netlink layouts cover the real headers; this locks the
-- format derivation independently of the generated output)
local codec = struct{ size = 16, fields = {
	{ name = "a", offset = 0, size = 1, signed = false },
	{ name = "b", offset = 2, size = 2, signed = false },
	{ name = "c", offset = 4, size = 4, signed = true  },
	{ name = "d", offset = 8, size = 4, signed = false },
} }
assert(codec.format == "=I1xI2i4I4xxxx", "format: " .. codec.format)
assert(codec.size == 16, "size: " .. codec.size)

-- pack/unpack round-trip, including the signed field with a negative value
local bytes = codec:pack(1, 2, -3, 4)
assert(#bytes == 16, "packed size: " .. #bytes)
local a, b, c, d = codec:unpack(bytes)
assert(a == 1 and b == 2 and c == -3 and d == 4, "round-trip")

-- fieldsize reports a named field's width; unknown names yield nil
assert(codec:fieldsize("b") == 2, "fieldsize")
assert(codec:fieldsize("nope") == nil, "fieldsize unknown")

-- fields may be listed out of offset order; the codec sorts by offset
local unordered = struct{ size = 4, fields = {
	{ name = "hi", offset = 2, size = 2, signed = false },
	{ name = "lo", offset = 0, size = 2, signed = false },
} }
assert(unordered.format == "=I2I2", "out-of-order: " .. unordered.format)
assert(unordered.fields[1].name == "lo" and unordered.fields[2].name == "hi", "fields in offset order")

-- a big-endian field switches the format's order for itself alone
local network = struct{size = 6, fields = {
	{name = "a", offset = 0, size = 1, signed = false},
	{name = "b", offset = 2, size = 2, signed = false, bigendian = true},
	{name = "c", offset = 4, size = 2, signed = false},
}}
assert(network.format == "=I1x>I2=I2", "big-endian: " .. network.format)
assert(network:pack(1, 0x1234, 0x5678):sub(3, 4) == "\x12\x34", "big-endian pack")

-- bitfields leave the format as the fields alone make it
local bitfields = struct{size = 6, fields = network.layout.fields, bitfields = {
	{name = "n", offset = 0, size = 2, signed = false, shift = 4, mask = 0xf},
}}
assert(bitfields.format == network.format, "bitfields: " .. bitfields.format)

-- overlapping fields (a union) are rejected
local ok = pcall(struct, { size = 4, fields = {
	{ name = "x", offset = 0, size = 4, signed = false },
	{ name = "y", offset = 0, size = 4, signed = false },
} })
assert(not ok, "overlapping fields must raise")

print("struct: all tests passed")

