--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink list_family test (see list_family.sh).

local netlink = require("netlink")
local af      = require("linux.socket").af

local format = string.format

local classes  = {"addr", "route", "rule"}
local families = {inet = af.INET, inet6 = af.INET6}

local function only(records, family)
	for _, record in ipairs(records) do
		if record.family ~= family then
			return false
		end
	end
	return #records > 0
end

for _, class in ipairs(classes) do
	local object <close> = netlink.rt[class]()
	for name, family in pairs(families) do
		if only(object:list{family = family}, family) then
			print(format("netlink list_family: %s %s", class, name))
		end
	end
end

