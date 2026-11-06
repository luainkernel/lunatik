--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the hid device test (see device.sh).

local hid    = require("hid")
local format = string.format

local BUS            <const> = 0x03   -- BUS_USB
local VENDOR         <const> = 0xf055 -- the peer's devices carry it, and no other device on the hid bus does
local DRIVER_DATA    <const> = 42
local RAISE          <const> = 0x0003 -- the product whose probe raises
local BREAK          <const> = 0x0004 -- the product whose descriptor report_fixup breaks
local PRESENT        <const> = 0x0005 -- the product whose probe, which hid.register delivers, registers and stops
local HANDED         <const> = 0x0006 -- the product the handing driver holds until the body stops it
local HANDED_DATA    <const> = 7
local USAGE          <const> = 8      -- offset of the collection's usage in the peer's descriptor
local FIXED_USAGE    <const> = 0x03
local END_COLLECTION <const> = 0xc0
local EPROTO         <const> = 71
local MAX_ERRNO      <const> = 4095
local RAISED         <const> = "raised"

local loading = true -- cleared once the body returns, so a callback tells its delivery inside it
local handing

local function raises()
	error(RAISED, 0) -- no position, so the harness tells the case's raise from a failed assertion
end

local function passes()
end

local function zero()
	return 0
end

local function errno()
	return -EPROTO
end

local function positive()
	return 1
end

local function numeral()
	return tostring(-EPROTO)
end

local function beyond()
	return -(MAX_ERRNO + 1)
end

local answers = {[0] = passes, zero, errno, positive, numeral, beyond, raises} -- by the report's first byte

local function fix(rdesc)
	rdesc:setbyte(USAGE, FIXED_USAGE)
end

local function corrupt(rdesc)
	rdesc:setbyte(0, END_COLLECTION) -- closes a collection never opened, which the HID core fails to parse
end

local function seen(hdev)
	hdev.seen = hdev.seen + 1
end

local function released(hdev)
	print(format("hid/device: released %s", hdev.name))
end

local function phase()
	return loading and "loading" or "loaded"
end

local function nested()
	local ok, err = pcall(hid.register, {name = "lunatik_hid_nested", id_table = {{bus = BUS, vendor = VENDOR}}})
	print(format("hid/device: nested register %s", ok and "returned" or err))
	ok, err = pcall(handing.stop, handing)
	print(format("hid/device: nested stop %s", ok and "returned" or err))
end

local function probe(_, hdev, id)
	if hdev.product == RAISE then
		raises()
	elseif hdev.product == PRESENT then
		nested()
	end
	hdev.seen = 1
	if hdev.product == BREAK then
		setmetatable(hdev, {__gc = released}) -- its remove raises
	end
	print(format("hid/device: probe %s %04x %d %s", hdev.name, id.vendor, id.driver_data, phase()))
end

local function report_fixup(_, hdev, rdesc)
	seen(hdev)
	local fixup = hdev.product == BREAK and corrupt or fix
	fixup(rdesc)
end

local function raw_event(_, hdev, _, raw)
	seen(hdev)
	hdev.view = raw
	return answers[raw:getbyte(0)]()
end

local function remove(_, hdev)
	collectgarbage() -- finalizes the table of a device whose remove raised before
	seen(hdev)
	print(format("hid/device: remove %s %d %s", hdev.name, hdev.seen, phase()))
	if hdev.view ~= nil then
		local open = pcall(hdev.view.getbyte, hdev.view, 0)
		print(format("hid/device: view %s %s", hdev.name, open and "open" or "closed"))
	end
	if hdev.product == BREAK then
		raises()
	end
end

local function register(name, product, driver_data)
	return hid.register({
		name = name,
		id_table = {{bus = BUS, vendor = VENDOR, product = product, driver_data = driver_data}},
		probe = probe,
		report_fixup = report_fixup,
		raw_event = raw_event,
		remove = remove,
	})
end

handing = register("lunatik_hid_handing", HANDED, HANDED_DATA)
register("lunatik_hid_device", nil, DRIVER_DATA)

handing:stop() -- the device it holds goes to lunatik_hid_device, which matches it too
loading = false

