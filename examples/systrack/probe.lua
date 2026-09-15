--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

local probe  = require("probe")
local systab = require("syscall.table")
local rcu    = require("rcu")

local track = rcu.table()
local names = {}

for symbol, address in pairs(systab) do
	names[address] = names[address] == nil and symbol or false
end

local function count(address)
	local symbol = names[address]
	track[symbol] = (track[symbol] or 0) + 1
end

local handlers = {pre = count}

for address, symbol in pairs(names) do
	if symbol then
		probe.new(address, handlers)
	end
end

return function()
	return track
end

