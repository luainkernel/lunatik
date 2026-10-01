--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.ifindex and linux.hwaddr test (see hwaddr.sh).

local linux = require("linux")
local test  = require("tests.lib").test
local moved = require("tests.linux.hwaddr_index").moved

local byte   = string.byte
local pack   = table.pack
local format = string.format
local rep    = string.rep

local LOOPBACK  <const> = "lo"
local LOOPINDEX <const> = 1 -- LOOPBACK_IFINDEX
local DEV       <const> = "lunatikhw0" -- DEV in hwaddr.sh, in the initial namespace
local MOVED     <const> = "lunatikhw1" -- MOVED in hwaddr.sh, in a namespace of its own
local ETH_ALEN  <const> = 6

local MAXINDEX    <const> = (1 << 31) - 1 -- INT_MAX
local OUTOFBOUNDS <const> = "out of bounds"
local U32         <const> = 1 << 32 -- past the int an index is read into

local function none(what, f, arg)
	local answer = pack(f(arg))
	assert(answer.n == 1 and answer[1] == nil, format("%s answered %d values, the first %s", what, answer.n, tostring(answer[1])))
end

local function refuses(what, expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " was answered")
	assert(tostring(err):find(expected, 1, true), what .. " raised something else: " .. tostring(err))
end

local function sysfs(name, attribute)
	local file <close> = assert(io.open(format("/sys/class/net/%s/%s", name, attribute)))
	return file:read("l")
end

-- the hardware address as sysfs spells it
local function colons(addr)
	return format(rep("%02x", #addr, ":"), byte(addr, 1, -1))
end

test("linux.ifindex resolves a name to the index sysfs gives it", function()
	local loopback = linux.ifindex(LOOPBACK)
	assert(loopback == LOOPINDEX, "lo resolved to " .. loopback)
	local index = linux.ifindex(DEV)
	assert(index == tonumber(sysfs(DEV, "ifindex")), DEV .. " resolved to " .. index)
end)

test("linux.hwaddr answers the device's address, addr_len bytes long", function()
	local loopback = linux.hwaddr(linux.ifindex(LOOPBACK))
	assert(loopback == rep("\0", ETH_ALEN), "lo answered " .. colons(loopback))
	local addr = colons(linux.hwaddr(linux.ifindex(DEV)))
	assert(addr == sysfs(DEV, "address"), DEV .. " answered " .. addr)
end)

test("linux.ifindex and linux.hwaddr answer nil for a device of another namespace", function()
	none("the moved device's name", linux.ifindex, MOVED)
	none("the moved device's index", linux.hwaddr, moved)
end)

test("linux.hwaddr refuses an index outside 1 to INT_MAX", function()
	refuses("lo's index past 32 bits", OUTOFBOUNDS, linux.hwaddr, LOOPINDEX | U32)
	refuses("an index of 0", OUTOFBOUNDS, linux.hwaddr, 0)
	refuses("a negative index", OUTOFBOUNDS, linux.hwaddr, -1)
	refuses("an index past INT_MAX", OUTOFBOUNDS, linux.hwaddr, MAXINDEX + 1)
end)

