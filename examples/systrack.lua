--
-- Copyright (c) 2024 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

local linux  = require("linux")
local probe  = require("probe")
local device = require("device")
local systab = require("syscall.table")

local syscalls = {"openat", "read", "write", "readv", "writev", "close"}

local function nop() end -- do nothing

local s = linux.stat
local driver = {name = "systrack", open = nop, release = nop, mode = s.IRUGO}

local track = {}
local toggle = true
function driver:read()
	local log = ""
	if toggle then
		for symbol, counter in pairs(track) do
			log = log .. string.format("%s: %d\n", symbol, counter)
		end
	end
	toggle = not toggle
	return log
end

for _, symbol in ipairs(syscalls) do
	local address = systab[symbol]
	track[symbol] = 0

	local function handler()
		track[symbol] = track[symbol] + 1
	end

	probe.new(address, {pre = handler, post = nop})
end

device.new(driver)

