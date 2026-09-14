--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kprobe_concurrent regression test (see kprobe_concurrent.sh).
--

local probe  = require("probe")
local systab = require("syscall.table")
local rcu    = require("rcu")
local data   = require("data")

local track = rcu.table()
local hits = data.new(8)

for symbol, address in pairs(systab) do
	local function handler()
		track[symbol] = (track[symbol] or 0) + 1
		hits:setnumber(0, hits:getnumber(0) + 1)
	end
	probe.new(address, {pre = handler})
end

