--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- FIB rule (policy routing) interface. A `netlink.session` specialization over
-- the `NETLINK_ROUTE` protocol: create an instance with `netlink.rt.rule()`,
-- then add, delete and list FIB rules; the underlying socket is closed by
-- `close()` (or the to-be-closed `__close`). All methods block and require a
-- sleepable runtime.
--
-- @module netlink.rt.rule
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local insert = table.insert
local pack   = string.pack
local u32 = message.u32

local fib_rule     = struct(rtnl.layout.fib_rule_hdr)
local FIB_RULE_LEN = fib_rule.size

-- ids that do not fit the u8 table header field go in the TABLE attribute
local TABLE_MAX = (1 << 8 * fib_rule:fieldsize("table")) - 1

local NEWRULE, DELRULE, GETRULE = rtnl.rtm.NEWRULE, rtnl.rtm.DELRULE, rtnl.rtm.GETRULE

---
-- @type rule

---
-- Creates a new rule object.
-- @function rule:new
-- @tparam[opt] table o an initial object table.
-- @treturn rule the new rule object.
-- @see class
local rule = session:new{proto = nl.proto.ROUTE}

---
-- Lists all FIB rules from the kernel.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of rule tables.
function rule:list(family)
	local header = fib_rule:pack(family or sk.af.UNSPEC, 0, 0, 0, 0, 0, 0)
	local rules = {}
	for _, msg in ipairs(self:dump(GETRULE, header)) do
		if msg.type == NEWRULE then
			local body = msg.body
			local fam, _, _, _, tbl, action, flags = fib_rule:unpack(body)
			local attrs = message.attrs(body, FIB_RULE_LEN + 1)
			insert(rules, {
				family = fam, action = action, flags = flags,
				table = u32(attrs[rtnl.fra.TABLE]) or tbl,
				priority = u32(attrs[rtnl.fra.PRIORITY]),
				fwmark = u32(attrs[rtnl.fra.FWMARK]),
			})
		end
	end
	return rules
end

-- add and delete send the same rule; only the message type and flags differ
local function rule_message(opts)
	local tbl = opts.table or rtnl.table.MAIN
	local header = fib_rule:pack(opts.family or sk.af.INET, 0, 0, 0,
		tbl <= TABLE_MAX and tbl or rtnl.table.UNSPEC, opts.action or rtnl.fr_act.TO_TBL, 0)
	return header .. message.attrs{
		[rtnl.fra.TABLE]    = opts.table and opts.table > TABLE_MAX and opts.table or nil,
		[rtnl.fra.PRIORITY] = opts.priority,
		[rtnl.fra.FWMARK]   = opts.fwmark,
		[rtnl.fra.PROTOCOL] = opts.protocol and pack("B", opts.protocol) or nil,
	}
end

---
-- Adds a FIB rule directing matching lookups to a routing table.
-- @tparam table opts rule parameters: optional `family` (default `AF_INET`),
--   `table`, `priority`, `fwmark`, `protocol`, `action` (default `FR_ACT_TO_TBL`).
function rule:add(opts)
	self:talk(NEWRULE, nl.flag.CREATE | nl.flag.EXCL, rule_message(opts))
end

---
-- Deletes a FIB rule matching the given parameters.
-- @tparam table opts rule parameters: optional `family` (default `AF_INET`),
--   `table`, `priority`, `fwmark`.
function rule:del(opts)
	self:talk(DELRULE, nil, rule_message(opts))
end

return rule

