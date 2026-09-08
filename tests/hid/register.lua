--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the hid id_table test (see run.sh).

local hid  = require("hid")
local test = require("util").test
local insert = table.insert

local BUS      <const> = 0x03   -- BUS_USB
local VENDOR   <const> = 0xf055 -- no device on the hid bus carries this vendor, so nothing binds
local MAXIDS   <const> = 4096   -- LUAHID_MAXIDS, the longest id_table hid.register serves
local HUGE_IDS <const> = 1 << 40

local function hugelen()
	return HUGE_IDS
end

local function ids(n)
	local id_table = {}
	for i = 1, n do
		insert(id_table, {bus = BUS, vendor = VENDOR, product = i})
	end
	return id_table
end

local function register(name, id_table)
	hid.register({name = name, id_table = id_table})
end

local function refuses(name, id_table)
	local ok, err = pcall(register, name, id_table)
	assert(not ok, "hid.register accepted an id_table of " .. #id_table .. " entries")
	assert(err:match("'id_table' is too long"), "hid.register raised something else: " .. err)
end

test("hid.register accepts an id_table it serves", function()
	register("lunatik_hid_one", ids(1))
	register("lunatik_hid_max", ids(MAXIDS))
end)

test("hid.register refuses an id_table it cannot serve", function()
	refuses("lunatik_hid_over", ids(MAXIDS + 1))
end)

test("hid.register refuses a fabricated id_table length", function()
	refuses("lunatik_hid_huge", setmetatable({}, {__len = hugelen}))
end)

