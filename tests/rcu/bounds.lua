--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the rcu.table bounds test (see run.sh).

local rcu  = require("rcu")
local test = require("util").test

local MAXSIZE <const> = 1 << 60 -- LUARCU_MAXSIZE, past which sizing the table wraps on a 64-bit kernel
local UNSERVED <const> = 1 << 58 -- sizeable, and past what any allocator serves

local accepted <const> = {1, 2, 3, 256, 4096, 1 << 20}
local refused  <const> = {0, -1, MAXSIZE + 1, 1 << 61, math.maxinteger, math.mininteger}

local function refuses(buckets)
	local ok, err = pcall(rcu.table, buckets)
	assert(not ok, "rcu.table accepted " .. buckets .. " buckets")
	assert(err:match("out of bounds"), "rcu.table raised something else: " .. err)
end

test("rcu.table defaults to a usable table", function()
	local t = rcu.table()
	t["k"] = 42
	assert(t["k"] == 42, "the default table lost its entry")
end)

test("rcu.table accepts a bucket count it serves", function()
	for _, buckets in ipairs(accepted) do
		local t = rcu.table(buckets)
		t["k"] = buckets
		assert(t["k"] == buckets, "the table of " .. buckets .. " buckets lost its entry")
	end
end)

test("rcu.table refuses a bucket count it cannot serve", function()
	for _, buckets in ipairs(refused) do
		refuses(buckets)
	end
end)

test("rcu.table leaves a count it can size to the allocator", function()
	local ok, err = pcall(rcu.table, UNSERVED)
	assert(not ok, "rcu.table served " .. UNSERVED .. " buckets")
	assert(err:match("not enough memory"), "rcu.table raised something else: " .. err)
end)

test("rcu.table refuses a value that is no integer", function()
	local ok, err = pcall(rcu.table, "x")
	assert(not ok, "rcu.table accepted a string")
	assert(err:match("number expected"), "rcu.table raised something else: " .. err)
end)

