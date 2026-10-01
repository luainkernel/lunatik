--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data bounds test (see run.sh).

local data = require("data")
local test = require("util").test

local PAGE    <const> = 4096
local MAXSIZE <const> = 0x7fffffff -- INT_MAX, the largest size data.new and data:resize serve
local MARK    <const> = 0x5a

local accepted <const> = {1, 8, PAGE, PAGE + 1, 1 << 20}
local refused  <const> = {0, -1, MAXSIZE + 1, math.maxinteger, math.mininteger}

local widths <const> = {
	{bits = 8,  set = {"setint8", "setuint8", "setbyte"}, signed = "getint8",  unsigned = "getuint8"},
	{bits = 16, set = {"setint16", "setuint16"},           signed = "getint16", unsigned = "getuint16"},
	{bits = 32, set = {"setint32", "setuint32"},           signed = "getint32", unsigned = "getuint32"},
}

local function refuses(what, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " accepted a value out of its bounds")
	assert(err:match("out of bounds"), what .. " raised something else: " .. err)
end

local function takes(d, width, setter, value, signed, unsigned)
	d[setter](d, 0, value)
	local gotsigned, gotunsigned = d[width.signed](d, 0), d[width.unsigned](d, 0)
	local read = ("%s(%d) reads back %d and %d"):format(setter, value, gotsigned, gotunsigned)
	assert(gotsigned == signed and gotunsigned == unsigned, read)
end

test("data.new accepts a size it serves", function()
	for _, size in ipairs(accepted) do
		local d = data.new(size)
		assert(#d == size, "expected " .. size .. " bytes, got " .. #d)
		d:setbyte(size - 1, MARK)
		assert(d:getbyte(size - 1) == MARK, "the last byte of " .. size .. " did not survive")
	end
end)

test("data.new refuses a size it cannot serve", function()
	for _, size in ipairs(refused) do
		refuses("data.new", data.new, size)
	end
end)

test("data.new keeps taking a mode", function()
	assert(#data.new(8, "shared") == 8, "the shared mode lost the size")
	assert(#data.new(8, "single") == 8, "the single mode lost the size")
end)

test("data:resize accepts a size it serves", function()
	local d = data.new(8)
	d:setbyte(0, MARK)

	d:resize(PAGE * 2)
	assert(#d == PAGE * 2, "growing did not take, got " .. #d)
	assert(d:getbyte(0) == MARK, "growing lost the old bytes")

	d:resize(8)
	assert(#d == 8, "shrinking did not take, got " .. #d)
	assert(d:getbyte(0) == MARK, "shrinking lost the old bytes")
end)

test("data:resize refuses a size it cannot serve", function()
	local d = data.new(8)
	local resize = getmetatable(d).resize
	d:setbyte(0, MARK)
	for _, size in ipairs(refused) do
		refuses("data:resize", resize, d, size)
	end
	assert(#d == 8, "a refused resize changed the size to " .. #d)
	assert(d:getbyte(0) == MARK, "a refused resize dropped the buffer")
end)

test("an integer setter takes its width read signed or unsigned", function()
	local d = data.new(8)
	for _, width in ipairs(widths) do
		local half = 1 << (width.bits - 1)
		for _, setter in ipairs(width.set) do
			takes(d, width, setter, -half, -half, half)
			takes(d, width, setter, -1, -1, 2 * half - 1)
			takes(d, width, setter, 2 * half - 1, -1, 2 * half - 1)
			takes(d, width, setter, half - 1, half - 1, half - 1)
		end
	end
end)

test("an integer setter refuses a value past its width and keeps the bytes", function()
	local d = data.new(8)
	for _, width in ipairs(widths) do
		local half = 1 << (width.bits - 1)
		for _, setter in ipairs(width.set) do
			d[setter](d, 0, MARK)
			refuses(setter, d[setter], d, 0, 2 * half)
			refuses(setter, d[setter], d, 0, -half - 1)
			refuses(setter, d[setter], d, 0, (1 << 32) | MARK)
			assert(d[width.unsigned](d, 0) == MARK, setter .. " changed the bytes it refused")
		end
	end
end)

test("setint64 takes every integer", function()
	local d = data.new(8)
	for _, value in ipairs({math.mininteger, -1, math.maxinteger}) do
		d:setint64(0, value)
		local got = d:getint64(0)
		assert(got == value, "setint64(" .. value .. ") reads back " .. got)
	end
end)

