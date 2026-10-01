--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the rcu.table cycle refusal test (see run.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local test    = require("tests.lib").test

local MAXWALK <const> = 16 -- LUARCU_MAXWALK, the tables that hold tables a store walks
local ENVKEY  <const> = "tests_rcu_cycle"

local function store(t, key, value)
	t[key] = value
end

local function refuses(t, key, value)
	local ok, err = pcall(store, t, key, value)
	assert(not ok, "the store of " .. key .. " was accepted")
	assert(err:match("ELOOP"), "the store of " .. key .. " raised something else: " .. tostring(err))
end

-- n tables that hold tables, each holding the one below it, down to a table that holds none
local function chain(n)
	local top = rcu.table()
	for _ = 1, n do
		local holder = rcu.table()
		holder.below = top
		top = holder
	end
	return top
end

local function emptied(n)
	local holders = rcu.table()
	for i = 1, n do
		local holder = rcu.table()
		holder.leaf = rcu.table()
		holder.leaf = i % 2 == 0 and i or nil
		holders[tostring(i)] = holder
	end
	return holders
end

test("rcu.table refuses a table stored in itself", function()
	local t = rcu.table()
	refuses(t, "self", t)
	assert(t.self == nil, "the refused store left an entry")
end)

test("rcu.table refuses a table that holds the one it is stored in", function()
	local a, b = rcu.table(), rcu.table()
	a.b = b
	refuses(b, "a", a)
	assert(b.a == nil, "the refused store left an entry")
	assert(a.b ~= nil, "the refusal dropped the entry that closes the cycle")
end)

test("rcu.table refuses a table that reaches the one it is stored in through others", function()
	local a, b, c = rcu.table(), rcu.table(), rcu.table()
	a.b = b
	b.c = c
	refuses(c, "a", a)
	assert(c.a == nil, "the refused store left an entry")
end)

test("rcu.table keeps the value a refused store would replace", function()
	local a, b = rcu.table(), rcu.table()
	b.a = 1
	a.b = b
	refuses(b, "a", a)
	assert(b.a == 1, "the refused store replaced the value: " .. tostring(b.a))
end)

test("rcu.table refuses lunatik._ENV stored in a table it holds", function()
	local env = lunatik._ENV
	local t = rcu.table()
	env[ENVKEY] = t
	local ok, err = pcall(store, t, "env", env)
	env[ENVKEY] = nil
	assert(not ok, "the store of lunatik._ENV was accepted")
	assert(err:match("ELOOP"), "the store of lunatik._ENV raised something else: " .. tostring(err))
end)

test("rcu.table stores a table that reaches others but not the one it is stored in", function()
	local a, b, c, d, p = rcu.table(), rcu.table(), rcu.table(), rcu.table(), rcu.table()
	a.b = b
	a.c = c
	b.d = d
	c.d = d
	d.leaf = rcu.table()
	p.a = a
	assert(p.a ~= nil, "the store was lost")
end)

test("rcu.table counts an entry overwritten with a table", function()
	local a, b = rcu.table(), rcu.table()
	a.b = 1
	a.b = b
	refuses(b, "a", a)
end)

test("rcu.table counts the table an entry is replaced with, and not the one it held", function()
	local a, b, c = rcu.table(), rcu.table(), rcu.table()
	a.held = b
	a.held = c
	refuses(c, "a", a)
	b.a = a
	assert(b.a ~= nil, "the store was lost")
end)

test("rcu.table stores a table into one it no longer reaches", function()
	local a, b = rcu.table(), rcu.table()
	a.b = b
	a.b = nil
	b.a = a
	assert(b.a ~= nil, "the store was lost")
end)

test("rcu.table walks MAXWALK tables that hold tables and refuses one more", function()
	local p = rcu.table()
	p.x = chain(MAXWALK)
	assert(p.x ~= nil, "the store was lost")
	refuses(p, "y", chain(MAXWALK + 1))
end)

test("rcu.table does not count the tables that hold none", function()
	local wide, p = rcu.table(), rcu.table()
	for i = 1, 2 * MAXWALK do
		wide[tostring(i)] = rcu.table()
	end
	p.wide = wide
	assert(p.wide ~= nil, "the store was lost")
end)

test("rcu.table counts once a table held under several keys", function()
	local shared, top, p = chain(1), rcu.table(), rcu.table()
	for i = 1, 2 * MAXWALK do
		top[tostring(i)] = shared
	end
	p.top = top
	assert(p.top ~= nil, "the store was lost")
end)

test("rcu.table does not count a table whose tables were deleted or replaced", function()
	local p = rcu.table()
	p.holders = emptied(2 * MAXWALK)
	assert(p.holders ~= nil, "the store was lost")
end)

