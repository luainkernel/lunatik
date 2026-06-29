--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink route_adddel test (see route_adddel.sh).

local rt = require("netlink.rt")
local af = require("linux.socket").af
local scope = require("linux.rtnetlink").scope

local TABLE   = 1000                      -- isolated table; id > 255 exercises RTA_TABLE
local DST     = string.char(192, 0, 2, 0) -- 192.0.2.0 (TEST-NET-1), network byte order
local DST_LEN = 24
local LO      = 1                          -- loopback ifindex

local r <close> = rt()

local function present()
	for _, route in ipairs(r:route_dump(af.INET)) do
		if route.table == TABLE and route.dst == DST and route.dst_len == DST_LEN then
			return true
		end
	end
	return false
end

r:route_add{family = af.INET, dst = DST, dst_len = DST_LEN, oif = LO,
	table = TABLE, scope = scope.LINK}
assert(present(), "route not found after add")
print("netlink route_adddel: added")

-- route_add sends NLM_F_EXCL, so adding the same route again must raise
-- (EEXIST), surfaced by check_error from the kernel acknowledgment
assert(not pcall(r.route_add, r, {family = af.INET, dst = DST, dst_len = DST_LEN,
	oif = LO, table = TABLE, scope = scope.LINK}), "duplicate add should raise")
print("netlink route_adddel: duplicate add raises")

r:route_del{family = af.INET, dst = DST, dst_len = DST_LEN, oif = LO, table = TABLE}
assert(not present(), "route still present after del")
print("netlink route_adddel: deleted")

