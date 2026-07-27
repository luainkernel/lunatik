--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Kernel routing table interface. A `netlink.session` specialization over the
-- `NETLINK_ROUTE` protocol: create an instance with `netlink.rt.route()`, then
-- add, delete and list routes; the underlying socket is closed by `close()`
-- (or the to-be-closed `__close`). All methods block and require a sleepable
-- runtime.
--
-- @module netlink.rt.route
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local insert = table.insert
local u32 = message.u32

local rtmsg     = struct(rtnl.layout.rtmsg)
local RTMSG_LEN = rtmsg.size

-- ids that do not fit the u8 table header field go in the TABLE attribute
local TABLE_MAX = (1 << 8 * rtmsg:fieldsize("rtm_table")) - 1

local NEWROUTE, DELROUTE, GETROUTE = rtnl.rtm.NEWROUTE, rtnl.rtm.DELROUTE, rtnl.rtm.GETROUTE

---
-- @type route

---
-- Creates a new route object.
-- @function route:new
-- @tparam[opt] table o an initial object table.
-- @treturn route the new route object.
-- @see class
local route = session:new{proto = nl.proto.ROUTE}

---
-- Lists all routes from the kernel routing tables.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of route tables.
function route:list(family)
	local header = rtmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0, 0, 0, 0, 0)
	local routes = {}
	for _, msg in ipairs(self:dump(GETROUTE, header)) do
		if msg.type == NEWROUTE then
			local body = msg.body
			local fam, dst_len, src_len, tos, tbl, protocol, scope, rtype, flags = rtmsg:unpack(body)
			local attrs = message.attrs(body, RTMSG_LEN + 1)
			insert(routes, {
				family = fam, dst_len = dst_len, src_len = src_len, tos = tos,
				table = u32(attrs[rtnl.rta.TABLE]) or tbl,
				protocol = protocol, scope = scope, rtype = rtype, flags = flags,
				dst = attrs[rtnl.rta.DST], gateway = attrs[rtnl.rta.GATEWAY],
				oif = u32(attrs[rtnl.rta.OIF]),
				priority = u32(attrs[rtnl.rta.PRIORITY]),
			})
		end
	end
	return routes
end

local function route_attrs(opts)
	return message.attrs{
		[rtnl.rta.DST]     = opts.dst,
		[rtnl.rta.GATEWAY] = opts.gateway,
		[rtnl.rta.OIF]     = opts.oif,
		[rtnl.rta.TABLE]   = opts.table and opts.table > TABLE_MAX and opts.table or nil,
	}
end

---
-- Adds a route to the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `gateway`, `oif`, `table`, `protocol`, `scope`, `rtype`.
function route:add(opts)
	local tbl = opts.table or rtnl.table.MAIN
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		tbl <= TABLE_MAX and tbl or rtnl.table.UNSPEC, opts.protocol or rtnl.rtprot.STATIC,
		opts.scope or rtnl.scope.UNIVERSE, opts.rtype or rtnl.rtn.UNICAST, 0)
	self:talk(NEWROUTE, nl.flag.CREATE | nl.flag.EXCL, header .. route_attrs(opts))
end

---
-- Deletes a route from the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `oif`, `table`.
function route:del(opts)
	local tbl = opts.table or rtnl.table.MAIN
	-- scope NOWHERE is the deletion wildcard: match the route whatever its scope
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		tbl <= TABLE_MAX and tbl or rtnl.table.UNSPEC, 0, rtnl.scope.NOWHERE, 0, 0)
	self:talk(DELROUTE, nil, header .. route_attrs(opts))
end

return route

