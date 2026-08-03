--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink rule_adddel test (see rule_adddel.sh).

local netlink = require("netlink")
local af = require("linux.socket").af

local TABLE = 1000  -- isolated table; id > 255 exercises FRA_TABLE
local SMALL = 100   -- fits the u8 header field: no FRA_TABLE, listed via the header
local PRIO  = 32100 -- unusual priority so it does not clash with existing rules

local rule <close> = netlink.rt.rule()

local function present(tbl, prio)
	for _, entry in ipairs(rule:list(af.INET)) do
		if entry.table == tbl and entry.priority == prio then
			return true
		end
	end
	return false
end

rule:add{family = af.INET, table = TABLE, priority = PRIO}
assert(present(TABLE, PRIO), "rule not found after add")
print("netlink rule_adddel: added")

-- add sends NLM_F_EXCL, so adding the same rule again must raise
assert(not pcall(rule.add, rule, {family = af.INET, table = TABLE, priority = PRIO}),
	"duplicate add should raise")
print("netlink rule_adddel: duplicate add raises")

rule:del{family = af.INET, table = TABLE, priority = PRIO}
assert(not present(TABLE, PRIO), "rule still present after del")
print("netlink rule_adddel: deleted")

rule:add{family = af.INET, table = SMALL, priority = PRIO + 1}
assert(present(SMALL, PRIO + 1), "small-table rule not found after add")
print("netlink rule_adddel: small-table added")

rule:del{family = af.INET, table = SMALL, priority = PRIO + 1}
assert(not present(SMALL, PRIO + 1), "small-table rule still present after del")
print("netlink rule_adddel: small-table deleted")

