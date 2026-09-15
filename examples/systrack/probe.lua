--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

local probe  = require("probe")
local systab = require("syscall.table")
local rcu    = require("rcu")

local track = rcu.table()
local names = {}

-- syscall numbers the kernel does not implement can share one entry point, where a hit belongs to no name
for symbol, address in pairs(systab) do
	if names[address] == nil then
		names[address] = symbol
	else
		names[address] = false
	end
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

