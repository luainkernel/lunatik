--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the hid id_table test (see run.sh).

local hid  = require("hid")
local test = require("tests.lib").test
local insert = table.insert
local format = string.format

local BUS      <const> = 0x03   -- BUS_USB
local VENDOR   <const> = 0xf055 -- no device on the hid bus carries this vendor, so nothing binds
local MAXIDS   <const> = 4096   -- LUAHID_MAXIDS, the longest id_table hid.register serves
local MAXNAME  <const> = 255    -- NAME_MAX, the buffer the driver name and its terminator share
local HUGE_IDS <const> = 1 << 40
local HELD     <const> = "lunatik_hid_one" -- on the bus from the first case until the runtime stops
local U16      <const> = 1 << 16 -- past the __u16 bus and group
local U32      <const> = 1 << 32 -- past the __u32 vendor and product

local idfields   = {"bus", "group", "vendor", "product", "driver_data"}
local notnumbers = {"abc", "3", true}

-- past each field's type, with low bits that keep a truncating build's driver under VENDOR, where no device binds
local pastrange = {
	bus         = {BUS - U16, BUS | U16},
	group       = {-U16, U16},
	vendor      = {VENDOR - U32, VENDOR | U32},
	product     = {1 - U32, 1 | U32},
	driver_data = {-1},
}

-- under VENDOR, a bus of HID_BUS_ANY and a product of HID_ANY_ID match only its devices
local toprange = {bus = U16 - 1, group = U16 - 1, vendor = VENDOR, product = U32 - 1, driver_data = math.maxinteger}

local function hugelen()
	return HUGE_IDS
end

local function onelen()
	return 1
end

local function badlen()
	return "eight"
end

local function raise()
	error("id_table entry")
end

local function ids(n)
	local id_table = {}
	for i = 1, n do
		insert(id_table, {bus = BUS, vendor = VENDOR, product = i})
	end
	return id_table
end

local function badids(field, value)
	local entry = {vendor = VENDOR}
	entry[field] = value
	return {{vendor = VENDOR}, entry} -- the second entry, so the walk raises past a filled one
end

local function register(name, id_table)
	hid.register({name = name, id_table = id_table})
end

local function refuses(name, id_table, expected)
	local ok, err = pcall(register, name, id_table)
	assert(not ok, "hid.register accepted " .. name)
	assert(err:match(expected), "hid.register raised something else: " .. err)
	collectgarbage() -- run the refused driver's finalizer now, while the test can still see a crash
end

test("hid.register accepts an id_table it serves", function()
	register(HELD, ids(1))
	register("lunatik_hid_max", ids(MAXIDS))
end)

test("hid.register refuses an id_table it cannot serve", function()
	refuses("lunatik_hid_over", ids(MAXIDS + 1), "'id_table' is too long")
	refuses("lunatik_hid_huge", setmetatable({}, {__len = hugelen}), "'id_table' is too long")
	refuses("lunatik_hid_len", setmetatable({}, {__len = badlen}), "not an integer")
end)

test("hid.register refuses an entry it cannot read", function()
	refuses("lunatik_hid_entry", {{vendor = VENDOR}, 42}, "invalid id_table")
	refuses("lunatik_hid_raise", {setmetatable({}, {__index = raise})}, "id_table entry")
	refuses("lunatik_hid_walk", setmetatable({}, {__len = onelen, __index = raise}), "id_table entry")
end)

test("hid.register refuses an id field that is not a number", function()
	for _, field in ipairs(idfields) do
		for _, value in ipairs(notnumbers) do
			local expected = format("bad field '%s' %%(number expected, got %s%%)", field, type(value))
			refuses("lunatik_hid_" .. field, badids(field, value), expected)
		end
	end
end)

test("hid.register refuses an id field past its range", function()
	for field, values in pairs(pastrange) do
		local expected = format("bad field '%s' %%(out of bounds%%)", field)
		for _, value in ipairs(values) do
			refuses("lunatik_hid_" .. field, badids(field, value), expected)
		end
	end
end)

test("hid.register accepts an id field at the top of its range", function()
	register("lunatik_hid_top", {toprange})
end)

test("hid.register refuses a name that fills its buffer", function()
	local ok, err = pcall(register, string.rep("x", MAXNAME), ids(1))
	assert(not ok, "hid.register accepted a name with no room for its terminator")
	assert(err:match("'name' is too long"), "hid.register raised something else: " .. err)
	register(string.rep("x", MAXNAME - 1), ids(1))
end)

test("hid.register refuses a name another driver holds with the kernel's errno", function()
	refuses(HELD, ids(1), "^EBUSY$")
end)

test("hid.register serves the next driver after a refusal", function()
	register("lunatik_hid_after", ids(1))
end)

