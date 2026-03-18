--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Tests for the io library in kernel space.
-- Uses /proc/version for read-only tests and a tmpfile for write/seek tests.

local TMPFILE = "/tmp/lunatik_io_test"
local CONTENT = "hello lunatik\n"

-- io.type on non-file values
assert(io.type("x")  == false, "io.type(string) should be false")
assert(io.type(42)   == false, "io.type(number) should be false")
assert(io.type(nil)  == false, "io.type(nil) should be false")

-- open non-existent file
local f, err = io.open("/nonexistent/lunatik_io_test", "r")
assert(f == nil,            "open non-existent: expected nil")
assert(type(err) == "string", "open non-existent: expected error string")

-- open with unsupported mode
local f2 = io.open("/proc/version", "x")
assert(f2 == nil, "open with invalid mode should fail")

-- open /proc/version for reading
local f3 = assert(io.open("/proc/version", "r"))
assert(io.type(f3) == "file", "io.type on open file")

-- read("l"): one line without newline
local line = f3:read("l")
assert(type(line) == "string" and #line > 0, "read('l'): expected non-empty string")
assert(line:sub(-1) ~= "\n",                 "read('l'): must not include newline")

-- read past EOF returns nil
assert(f3:read("l") == nil, "read past EOF returns nil")

-- close and check type
f3:close()
assert(io.type(f3) == "closed file", "io.type after close")

-- read on closed file must raise
local ok, _ = pcall(function() f3:read("l") end)
assert(not ok, "read on closed file must raise")

-- read("L"): line with newline
local f4 = assert(io.open("/proc/version", "r"))
local lineL = f4:read("L")
assert(type(lineL) == "string", "read('L'): expected string")
assert(lineL:sub(-1) == "\n" or #lineL > 0, "read('L'): result non-empty")
f4:close()

-- read("a"): read entire file
local f5 = assert(io.open("/proc/version", "r"))
local all = f5:read("a")
assert(type(all) == "string" and #all > 0, "read('a'): expected non-empty string")
f5:close()

-- io.lines: iterate /proc/version
local nlines = 0
for l in io.lines("/proc/version") do
	assert(type(l) == "string", "io.lines: expected string per line")
	nlines = nlines + 1
end
assert(nlines > 0, "io.lines: expected at least one line")

-- write, read back, append, seek, read by count
local fw = assert(io.open(TMPFILE, "w"))
assert(fw:write(CONTENT),        "write: expected truthy")
assert(fw:flush(),               "flush: expected truthy")
fw:close()

local fr = assert(io.open(TMPFILE, "r"))
local got = fr:read("a")
assert(got == CONTENT, "read-back: got " .. tostring(got))
fr:close()

local fa = assert(io.open(TMPFILE, "a"))
fa:write(CONTENT)
fa:close()

local fr2 = assert(io.open(TMPFILE, "r"))
local got2 = fr2:read("a")
assert(got2 == CONTENT .. CONTENT, "append: got " .. tostring(got2))
fr2:close()

-- seek and read by count
local fs = assert(io.open(TMPFILE, "r"))
local size = fs:seek("end", 0)
assert(size == #CONTENT * 2, "seek('end'): size mismatch")
fs:seek("set", 0)
local chunk = fs:read(5)
assert(chunk == "hello", "read(5): got " .. tostring(chunk))
fs:seek("cur", 0)

-- file:lines iterator
fs:seek("set", 0)
local lcount = 0
for l in fs:lines() do
	assert(type(l) == "string", "file:lines: expected string")
	lcount = lcount + 1
end
assert(lcount == 2, "file:lines: expected 2 lines, got " .. tostring(lcount))
fs:close()

print("io: all tests passed")

