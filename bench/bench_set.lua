--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- In-kernel benchmark for luaset vs Lua table vs rcu (suffix-membership).
-- Run in a process-context runtime: lunatik run bench_set

local linux = require("linux")
local set   = require("set")
local rcu   = require("rcu")

-- measure the full cost of the {[d]=true} representation (table + interned
-- strings) as the heap delta of loading it from a clean baseline
collectgarbage()
local base = collectgarbage("count")
local LIST = require("bypass")
collectgarbage()
local table_mem = collectgarbage("count") - base

local REP = 200

local sub, find = string.sub, string.find

-- faithful dome path: Lua suffix-walk over a key/value store
local function walk(store, dom)
	local i = 1
	while true do
		if store[sub(dom, i)] then return true end
		local dot = find(dom, '.', i, true)
		if not dot then return false end
		i = dot + 1
	end
end

-- queries: a subdomain of each key (forces a multi-step walk that hits)
local queries = {}
for d in pairs(LIST) do
	table.insert(queries, "www." .. d)
end
local nq = #queries

local function bench(name, fn)
	collectgarbage()
	fn() -- warm
	local t0 = linux.time()
	local hits = fn()
	local dt = linux.difftime(linux.time(), t0) -- nanoseconds
	local total = REP * nq
	print(string.format("%-34s %5d ns/lookup  %4d Mlookup/s  hits=%d",
		name, dt // total, (total * 1000) // dt, hits))
end

-- build the three representations
local keys = {}
for d in pairs(LIST) do table.insert(keys, d) end
local s = set.new(keys)

local rt = rcu.table(1 << 20)
for d in pairs(LIST) do rt[d] = true end

print(string.format("entries=%d  reps=%d  total=%d lookups/bench", nq, REP, REP * nq))

-- luaset cost is deterministic: raw key bytes + one uint32 offset per key
local n, raw = 0, 0
for d in pairs(LIST) do n = n + 1; raw = raw + #d end
local set_bytes = raw + (n + 1) * 4

print(string.format("MEM table {[d]=true} : %9d B  (~%d B/key)", table_mem, table_mem // n))
print(string.format("MEM luaset blob+off  : %9d B  (~%d B/key)  [%d blob + %d off]  -> %dx smaller",
	set_bytes, set_bytes // n, raw, (n + 1) * 4, table_mem // set_bytes))

bench("table suffix-walk (current dome)", function()
	local h = 0
	for _ = 1, REP do for j = 1, nq do if walk(LIST, queries[j]) then h = h + 1 end end end
	return h
end)

bench("rcu suffix-walk", function()
	local h = 0
	for _ = 1, REP do for j = 1, nq do if walk(rt, queries[j]) then h = h + 1 end end end
	return h
end)

bench("luaset:has (C, zero-alloc)", function()
	local h = 0
	for _ = 1, REP do for j = 1, nq do if s:has(queries[j], ".") then h = h + 1 end end end
	return h
end)

