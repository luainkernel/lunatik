--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- In-kernel memory: real merged dome blocklist as Lua table vs luaset.
-- lunatik run bench_domelist

local set = require("set")

-- Lua-table cost = kernel heap delta of loading the {[d]=true} representation
collectgarbage()
local base = collectgarbage("count")
local LIST = require("domelist")
collectgarbage()
local table_mem = collectgarbage("count") - base

local n, raw = 0, 0
for d in pairs(LIST) do n = n + 1; raw = raw + #d end
local set_bytes = raw + (n + 1) * 4

-- luaset stores its keys in kvmalloc, outside the Lua GC heap
local keys = {}
for d in pairs(LIST) do table.insert(keys, d) end

collectgarbage()
local before = collectgarbage("count")
local s = set.new(keys)
collectgarbage()
local set_heap = collectgarbage("count") - before

local M = 1048576
print(string.format("entries=%d  raw=%d B (~%d B/key)", n, raw, raw // n))
print(string.format("Lua table {[d]=true} : %9d B = %5d KiB  (~%d B/key)  [in Lua GC heap]",
	table_mem, table_mem // 1024, table_mem // n))
print(string.format("luaset structure     : %9d B = %5d KiB  (~%d B/key)  [via kvmalloc]",
	set_bytes, set_bytes // 1024, set_bytes // n))
print(string.format("luaset Lua-heap delta: %9d B  (data lives outside the GC heap)", set_heap))
print(string.format("reduction            : %d.%02dx  (saves %d KiB)",
	table_mem // set_bytes, (table_mem * 100 // set_bytes) % 100, (table_mem - set_bytes) // 1024))
print(string.format("#set = %d", #s))

