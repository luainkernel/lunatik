--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the cycle_release test, its stores from a kprobe (see cycle_release.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local rcu    = require("rcu")

local a, b = rcu.table(), rcu.table()

local temporary = rcu.table()
a.temporary = temporary
temporary = nil
collectgarbage() -- the handle: a's entry holds the table's only reference

local function store(t, key, value)
	t[key] = value
end

local function report(what)
	print("rcu cycle_hook: " .. what)
end

local function pre()
	a.b = b
	local ok, err = pcall(store, b, "a", a)
	if not ok and err:match("ELOOP") then
		report("refused")
	end
	a.b = nil
	b.a = a
	b.a = nil
	report("stored")
	a.temporary = nil -- the table's release runs here, in the handler
end

probe.new(systab["personality"], {pre = pre})

