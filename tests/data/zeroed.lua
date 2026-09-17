--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data zeroing test (see run.sh).

local lunatik = require("lunatik")
local test    = require("util").test
local zeroing = require("tests.data.zeroing")

local PAGE   <const> = 4096
local BLOCK  <const> = 64   -- the kmalloc cache a batch recycles through
local SHORT  <const> = 48   -- a growth from SHORT to BLOCK stays inside the block kmalloc served
local BIG    <const> = 1 << 20
local ROUNDS <const> = 16
local SCRIPT <const> = "tests/data/zeroed_atomic"

test("data.new zeroes a buffer krealloc serves", function()
	zeroing.newrounds(ROUNDS, BLOCK)
	zeroing.newrounds(ROUNDS, PAGE) -- the largest size that arm takes
end)

test("data.new zeroes a buffer kvmalloc serves", function()
	zeroing.newrounds(ROUNDS, PAGE + 1)
end)

test("data.new zeroes a megabyte buffer", function()
	zeroing.checknew(BIG)
end)

test("data.new zeroes a single buffer too", function()
	zeroing.newrounds(ROUNDS, BLOCK, "single")
end)

test("data:resize zeroes a growth inside the block it holds", function()
	zeroing.growrounds(ROUNDS, SHORT, BLOCK)
end)

test("data:resize zeroes a growth through another allocation", function()
	zeroing.growrounds(ROUNDS, BLOCK, PAGE * 2)
end)

test("data:resize zeroes a growth back into the block a shrink kept", function()
	zeroing.checkregrow(PAGE, BLOCK)
end)

test("an atomic runtime allocates zeroed buffers too", function()
	local runtime <close> = lunatik.runtime(SCRIPT, "softirq")
	runtime:resume()
end)

