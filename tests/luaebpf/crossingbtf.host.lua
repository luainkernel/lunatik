--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Writes the BTF of the struct crossing, for the btfview case (see btfview.sh).

local pack = string.pack

-- uapi/linux/btf.h: a btf_type's info holds its kind from bit 24 and a struct's kind_flag in bit 31, the
-- word after an INT its encoding from bit 24 and its bits, and a member's offset its bitfield size
-- from bit 24
local INT    <const> = 1 << 24
local STRUCT <const> = 1 << 31 | 4 << 24
local SIGNED <const> = 1 << 24
local BITS   <const> = 32

local strings = "\0unsigned int\0int\0crossing\0narrow\0negative\0wide\0uncovered\0"

local function name(text)
	return (strings:find("\0" .. text .. "\0", 1, true))
end

local function integer(text, encoding)
	return pack("<I4I4I4I4", name(text), INT, BITS // 8, encoding | BITS)
end

local function member(text, type, bit, bits)
	return pack("<I4I4I4", name(text), type, bits << 24 | bit)
end

local members = {member("narrow", 1, 0, 4), member("negative", 2, 4, 4), member("wide", 1, 20, 20),
	member("uncovered", 1, 40, 30)}
local types = integer("unsigned int", 0) .. integer("int", SIGNED) ..
	pack("<I4I4I4", name("crossing"), STRUCT | #members, 12) .. table.concat(members)
local file = assert(io.open(arg[1], "wb"))
assert(file:write(pack("<I2I1I1I4I4I4I4I4", 0xeb9f, 1, 0, 24, 0, #types, #types, #strings), types, strings))
assert(file:close())

