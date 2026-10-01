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
local USAGE          <const> = 8      -- offset of the collection's usage in the peer's descriptor
local FIXED_USAGE    <const> = 0x03
local END_COLLECTION <const> = 0xc0
local EPROTO         <const> = 71
local MAX_ERRNO      <const> = 4095
local RAISED         <const> = "raised"

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

local function probe(driver, hdev, id)
	if hdev.product == RAISE then
		raises()
	end
	hdev.seen = 1
	print(format("hid/device: probe %s %04x %d", hdev.name, id.vendor, id.driver_data))
end

local function report_fixup(driver, hdev, rdesc)
	seen(hdev)
	local fixup = hdev.product == BREAK and corrupt or fix
	fixup(rdesc)
end

local function raw_event(driver, hdev, report, raw)
	seen(hdev)
	return answers[raw:getbyte(0)]()
end

local function remove(driver, hdev)
	seen(hdev)
	print(format("hid/device: remove %s %d", hdev.name, hdev.seen))
end

hid.register({
	name = "lunatik_hid_device",
	id_table = {{bus = BUS, vendor = VENDOR, driver_data = DRIVER_DATA}},
	probe = probe,
	report_fixup = report_fixup,
	raw_event = raw_event,
	remove = remove,
})

