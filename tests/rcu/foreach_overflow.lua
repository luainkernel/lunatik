--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the foreach_overflow test (see foreach_overflow.sh).

local rcu  = require("rcu")
local data = require("data")

local unpack = table.unpack

local SIZE  <const> = 8
local WIDTH <const> = 220 -- argument counts spanning the walk's overflow window and the call's own

local pad = {}
for i = 1, WIDTH do
	pad[i] = true
end

local function noop() end

local function walk(t, ...) -- the varargs sit on the stack, so the walk's handle pcall overflows near the top
	rcu.foreach(t, noop)
end

local function attempt(t, k)
	walk(t, unpack(pad, 1, k))
end

for k = 0, WIDTH do
	local t = rcu.table(1)
	t.obj = data.new(SIZE)
	pcall(attempt, t, k)
end
collectgarbage() -- drop every table; each entry releases its data object here

print(string.format("foreach_overflow: %d objects", WIDTH + 1))

