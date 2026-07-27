--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink rule_adddel test (see rule_adddel.sh).

local netlink = require("netlink")
local af = require("linux.socket").af

local TABLE = 1000  -- isolated table; id > 255 exercises FRA_TABLE
local PRIO  = 32100 -- unusual priority so it does not clash with existing rules

local rule <close> = netlink.rt.rule()

local function present()
	for _, entry in ipairs(rule:list(af.INET)) do
		if entry.table == TABLE and entry.priority == PRIO then
			return true
		end
	end
	return false
end

rule:add{family = af.INET, table = TABLE, priority = PRIO}
assert(present(), "rule not found after add")
print("netlink rule_adddel: added")

-- add sends NLM_F_EXCL, so adding the same rule again must raise
assert(not pcall(rule.add, rule, {family = af.INET, table = TABLE, priority = PRIO}),
	"duplicate add should raise")
print("netlink rule_adddel: duplicate add raises")

rule:del{family = af.INET, table = TABLE, priority = PRIO}
assert(not present(), "rule still present after del")
print("netlink rule_adddel: deleted")

