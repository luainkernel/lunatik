--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the struct view test (see run.sh).

local data   = require("data")
local struct = require("struct")
local test   = require("tests.lib").test

local AT    <const> = 3
local TAIL  <const> = 8
local BYTES <const> = "\xf0\x90\xfe\xdc\xd4\xfe\x5a\x5a\xef\xbe\xad\xde\x18\xfc\xff\xff" ..
	"\x88\x77\x66\x55\x44\x33\x22\xf1\x01\x02\x03\x04\xfc\xff\xff\xff" ..
	"\xfe\xdc\xfe\xdc\x12\x34\x56\x78\x81\x02\x03\x04\x05\x06\x07\x08"

-- a field of every width and sign, a gap the codec reads as padding, two fields named as what the
-- view is handed, and big-endian fields of every width, one signed
local codec = struct{size = 48, fields = {
	{name = "u8", offset = 0, size = 1, signed = false},
	{name = "i8", offset = 1, size = 1, signed = true},
	{name = "u16", offset = 2, size = 2, signed = false},
	{name = "i16", offset = 4, size = 2, signed = true},
	{name = "u32", offset = 8, size = 4, signed = false},
	{name = "i32", offset = 12, size = 4, signed = true},
	{name = "u64", offset = 16, size = 8, signed = false},
	{name = "data", offset = 24, size = 4, signed = false},
	{name = "at", offset = 28, size = 4, signed = true},
	{name = "be16", offset = 32, size = 2, signed = false, bigendian = true},
	{name = "bei16", offset = 34, size = 2, signed = true, bigendian = true},
	{name = "be32", offset = 36, size = 4, signed = false, bigendian = true},
	{name = "be64", offset = 40, size = 8, signed = false, bigendian = true},
}}

-- what the big-endian fields hold, whatever the host's byte order
local big = {be16 = 0xfedc, bei16 = 0xfedc - 0x10000, be32 = 0x12345678, be64 = 0x8102030405060708}

-- the bytes from AT, past AT bytes the view has to skip
local buffer = data.new(AT + #BYTES)
buffer:setstring(AT, BYTES)

local function raises(what, f, message)
	local ok, err = pcall(f)
	assert(not ok, what .. " did not raise")
	assert(message == nil or tostring(err):find(message, 1, true), what .. " raised " .. tostring(err))
end

test("a view reads every field as unpack reads it off the same bytes", function()
	local values, view = {codec:unpack(BYTES)}, codec:view(buffer, AT)
	for i, field in ipairs(codec.fields) do
		local got = view[field.name]
		assert(got == values[i], ("%s reads %s, unpack %s"):format(field.name, got, values[i]))
	end
end)

test("a big-endian field reads its first byte as the most significant, with its sign", function()
	local view = codec:view(buffer, AT)
	for name, value in pairs(big) do
		assert(view[name] == value, ("%s reads %s, not %s"):format(name, view[name], value))
	end
end)

test("a field past the end of the data raises, and one before it reads", function()
	local tail = codec:view(buffer, #buffer - TAIL) -- the last TAIL bytes hold u8 and none of the fields read below
	assert(tail.u8 == buffer:getbyte(#buffer - TAIL), "u8 does not read the first byte of the tail")
	raises("u64 past the end", function() return tail.u64 end, "out of bounds")
	raises("be16 past the end", function() return tail.be16 end, "out of bounds")
end)

test("an assignment raises, and the field reads what it read", function()
	local view = codec:view(buffer, AT)
	local before = view.u16
	raises("an assignment", function() view.u16 = 1 end, "struct: a view is read-only")
	assert(view.u16 == before, "the assignment changed what u16 reads")
end)

test("a name the layout lacks raises", function()
	local view = codec:view(buffer, AT)
	raises("a read of 'missing'", function() return view.missing end)
end)

