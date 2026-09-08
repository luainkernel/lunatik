--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the idtable_leak test (see idtable_leak.sh).

local data = require("data")
local hid = require("hid")
local insert = table.insert

local MAXIDS <const> = 4096 -- LUAHID_MAXIDS, so each refusal strands the largest block one can
local BLOCK <const> = (MAXIDS + 1) * 24 -- sizeof(struct hid_device_id) is 24 on a 64-bit kernel
local REFUSALS <const> = 512 -- that many blocks is 64 MiB, far past the noise in SUnreclaim
local ENOMEM <const> = "not enough memory"
local SKIP <const> = "hid/idtable_leak: the kernel could not serve a block of this size" -- read by the .sh

PROBE = {} -- global: measured alive, so a freed id_table reads apart from a size the counter ignores

local function raise()
	error("id_table entry")
end

local entry = setmetatable({}, {__index = raise})

local function entrylen()
	return MAXIDS
end

local function pushentry()
	return entry
end

local id_table = setmetatable({}, {__len = entrylen, __index = pushentry})

local function walked()
	local ok, err = pcall(hid.register, {name = "lunatik_leak", id_table = id_table})
	assert(not ok, "hid.register accepted an id_table whose entries raise")
	if err:match(ENOMEM) then
		return false
	end
	assert(err:match("id_table entry"), "hid.register refused before it allocated: " .. err)
	return true
end

local function fill()
	for _ = 1, REFUSALS do
		insert(PROBE, data.new(BLOCK))
	end
end

for _ = 1, REFUSALS do
	if not walked() then
		print(SKIP)
		return
	end
end

if not pcall(fill) then
	print(SKIP)
end

