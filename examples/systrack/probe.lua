--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

local probe  = require("probe")
local systab = require("syscall.table")
local rcu    = require("rcu")

local track = rcu.table()

for symbol, address in pairs(systab) do
	local function handler()
		track[symbol] = (track[symbol] or 0) + 1
	end
	probe.new(address, {pre = handler})
end

local function attacher()
	return track
end
return attacher

