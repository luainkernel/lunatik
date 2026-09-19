--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.lookup test (see run.sh).
--

local linux = require("linux")
local lunatik = require("lunatik")
local test = require("util").test

local UNNAMEABLE <const> = "lunatik no such symbol" -- a space, which no compiler emits into a symbol
local ABSENT     <const> = "lunatik_no_such_symbol_926"
local PRESENT    <const> = "kallsyms_lookup_name" -- text, so kallsyms carries it without CONFIG_KALLSYMS_ALL
local RECEIVER   <const> = "tests/linux/lookup_recv"

test("linux.lookup answers nil for a name no build can emit", function()
	local addr = linux.lookup(UNNAMEABLE)
	assert(addr == nil, "expected nil, got " .. tostring(addr))
end)

test("linux.lookup answers nil for an absent symbol", function()
	local addr = linux.lookup(ABSENT)
	assert(addr == nil, "expected nil, got " .. tostring(addr))
end)

test("linux.lookup answers a lightuserdata for a symbol kallsyms carries", function()
	local addr = linux.lookup(PRESENT)
	assert(type(addr) == "userdata", "expected userdata for " .. PRESENT .. ", got " .. type(addr))
end)

test("linux.lookup rejects an argument that is not a string", function()
	local ok, err = pcall(linux.lookup, true)
	assert(not ok, "expected an error")
	assert(err:match("string expected"), "raised something else: " .. err)
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("linux.lookup answers an armed softirq runtime", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
	runtime:resume()
end)

test("linux.lookup answers an armed hardirq runtime", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "hardirq")
	runtime:resume()
end)

