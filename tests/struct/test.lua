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

-- fields may be listed out of offset order; the codec sorts by offset
local unordered = struct{ size = 4, fields = {
	{ name = "hi", offset = 2, size = 2, signed = false },
	{ name = "lo", offset = 0, size = 2, signed = false },
} }
assert(unordered.format == "=I2I2", "out-of-order: " .. unordered.format)

-- overlapping fields (a union) are rejected
local ok = pcall(struct, { size = 4, fields = {
	{ name = "x", offset = 0, size = 4, signed = false },
	{ name = "y", offset = 0, size = 4, signed = false },
} })
assert(not ok, "overlapping fields must raise")

print("struct: all tests passed")

