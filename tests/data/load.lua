--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data load test (see run.sh).

local lunatik = require("lunatik")
local data    = require("data")
local test    = require("tests.lib").test

local SCRATCH  <const> = "/tmp/lunatik-data/"
local BYTES    <const> = "0123456789abcdef" -- BYTES in run.sh
local MAX      <const> = 4096
local MAXSIZE  <const> = 0x7fffffff -- INT_MAX, the largest size data.new and data:resize serve
local GROWN    <const> = 64
local RECEIVER <const> = "tests/data/load_recv"
local REFUSAL  <const> = "not allowed once the runtime is armed"
local VMALLOC  <const> = "/proc/vmallocinfo"
local READER   <const> = "kernel_read_file"

local function path(name)
	return SCRATCH .. name
end

-- the blocks vmalloc gave kernel_read_file and that are still held
local function readerblocks()
	local n = 0
	for line in io.lines(VMALLOC) do
		if line:find(READER, 1, true) then
			n = n + 1
		end
	end
	return n
end

local function raises(expected, ...)
	local ok, err = pcall(data.load, ...)
	assert(not ok, "loaded what should raise " .. expected)
	assert(err:find(expected, 1, true), "raised '" .. tostring(err) .. "', not " .. expected)
end

local function resume(context)
	local runtime <close> = lunatik.runtime(RECEIVER, context)
	return pcall(runtime.resume, runtime)
end

local function refused(context)
	local ok, err = resume(context)
	assert(not ok, "an armed " .. context .. " runtime loaded a file")
	assert(err:match(REFUSAL), "an armed " .. context .. " runtime raised something else: " .. err)
end

test("data.load holds the file's bytes, and its buffer takes writes", function()
	local d = data.load(path("bytes"), MAX)
	assert(#d == #BYTES, "loaded " .. #d .. " bytes of " .. #BYTES)
	assert(tostring(d) == BYTES, "loaded '" .. tostring(d) .. "'")
	d:setbyte(0, 0x5a)
	assert(d:getbyte(0) == 0x5a, "a write to the loaded buffer did not stick")
end)

test("data.load reads into a block of the runtime's allocator, not one kernel_read_file takes from vmalloc", function()
	local before = readerblocks()
	local d = data.load(path("bytes"), MAX)
	assert(readerblocks() == before and #d == #BYTES, "the loaded buffer is a vmalloc of kernel_read_file's")
end)

test("data.load reads a file of maxbytes and raises EFBIG past it", function()
	assert(#data.load(path("bytes"), #BYTES) == #BYTES, "a file of maxbytes did not load")
	raises("EFBIG", path("bytes"), #BYTES - 1)
end)

test("data.load refuses a maxbytes outside [1, INT_MAX]", function()
	raises("out of bounds", path("bytes"), 0)
	raises("out of bounds", path("bytes"), MAXSIZE + 1)
end)

test("data.load raises the errno its read fails with", function()
	raises("ENOENT", path("missing"), MAX)
	raises("EINVAL", path("zero"), MAX)
	raises("EINVAL", path("dir"), MAX)
	raises("ETXTBSY", path("busy"), MAX)
end)

test("a loaded buffer resizes, keeping its bytes", function()
	local d = data.load(path("bytes"), MAX)
	d:resize(GROWN)
	assert(d:getstring(0, #BYTES) == BYTES and d:getbyte(GROWN - 1) == 0, "the grown buffer lost its bytes")
	d:resize(1)
	assert(#d == 1 and d:getstring(0) == BYTES:sub(1, 1), "the shrunk buffer lost its first byte")
end)

test("data.load loads in a process runtime past its body", function()
	local ok, err = resume("process")
	assert(ok, err)
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("data.load refuses an armed softirq runtime", function()
	refused("softirq")
end)

test("data.load refuses an armed hardirq runtime", function()
	refused("hardirq")
end)

