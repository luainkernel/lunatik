--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local probe   = require("probe")
local syscall = require("syscall.table")
local data    = require("data")

local systrack = lunatik._ENV.systrack

local function nop() end -- do nothing

local function inc(counter)
	counter:setnumber(0, counter:getnumber(0) + 1)
end

local sizeofnumber = string.packsize("n")

for symbol, address in pairs(syscall) do
	systrack[symbol] = data.new(sizeofnumber)

	local function handler()
		inc(systrack[symbol])
	end

	probe.new(address, {pre = handler, post = nop})
end

