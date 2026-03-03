--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local linux  = require("linux")
local probe  = require("probe")
local device = require("device")
local systab = require("syscall.table")

local syscalls = {"openat", "read", "write", "readv", "writev", "close"}

local s = linux.stat
local driver = {name = "systrack", mode = s.IRUGO}

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

	probe.new(address, {pre = handler})
end

device.new(driver)

