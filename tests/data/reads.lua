--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data reads test (see run.sh).

local data = require("data")
local test = require("tests.lib").test

local packsize, unpack = string.packsize, string.unpack

local ONES <const> = 0xffff

-- an odd length, so that a sum to the end pads its last byte, and high bits, so that a signed read
-- has a sign to extend
local BYTES <const> = "\x00\x01\xf2\x03\xf4\xf5\xf6\xf7\x80\x7f\xff"

local getters <const> = {
	getint8 = "=i1", getuint8 = "=I1", getbyte = "=I1", getint16 = "=i2", getuint16 = "=I2",
	getint32 = "=i4", getuint32 = "=I4", getint64 = "=i8",
}

local function buffer()
	local d = data.new(#BYTES)
	d:setstring(0, BYTES)
	return d
end

-- the Internet checksum of s (RFC 1071), each word read in host order, as data:checksum answers it
local function checksum(s)
	s = #s % 2 == 0 and s or s .. "\0"
	local sum = 0
	for i = 1, #s, 2 do
		sum = sum + unpack("=I2", s, i)
	end
	while sum > ONES do
		sum = (sum & ONES) + (sum >> 16)
	end
	return ~sum & ONES
end

test("each integer getter reads the bytes at each offset it fits", function()
	local d = buffer()
	for getter, format in pairs(getters) do
		for offset = 0, #BYTES - packsize(format) do
			local got, expected = d[getter](d, offset), unpack(format, BYTES, offset + 1)
			assert(got == expected, ("%s(%d) read %d, not %d"):format(getter, offset, got, expected))
		end
	end
end)

test("getstring, tostring and checksum read the bytes of each span", function()
	local d = buffer()
	assert(tostring(d) == BYTES, "tostring read other bytes")
	for offset = 0, #BYTES do
		assert(d:getstring(offset) == BYTES:sub(offset + 1), "getstring(" .. offset .. ") read other bytes")
		for length = 0, #BYTES - offset do
			local span = BYTES:sub(offset + 1, offset + length)
			local what = ("(%d, %d)"):format(offset, length)
			assert(d:getstring(offset, length) == span, "getstring" .. what .. " read other bytes")
			local got, expected = d:checksum(offset, length), checksum(span)
			assert(got == expected, ("checksum%s gave %#x, not %#x"):format(what, got, expected))
		end
	end
end)

