--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- rtnetlink interface for routes, links and addresses. A `netlink.session`
-- specialization over the `NETLINK_ROUTE` protocol: create an instance with
-- `rt()` and call its methods; the underlying socket is closed by `close()`
-- (or the to-be-closed `__close`). All methods block and require a sleepable
-- runtime.
--
-- @module netlink.rt
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local insert = table.insert
local unpack = string.unpack

local rtmsg     = struct(rtnl.layout.rtmsg)
local RTMSG_LEN = rtmsg.size
local ifinfomsg  = struct(rtnl.layout.ifinfomsg)
local IFINFO_LEN = ifinfomsg.size
local ifaddrmsg  = struct(rtnl.layout.ifaddrmsg)
local IFADDR_LEN = ifaddrmsg.size

local function fieldsize(layout, name)
	for _, field in ipairs(layout.fields) do
		if field.name == name then return field.size end
	end
end

-- ids that do not fit the rtm_table header field go in the RTA_TABLE attribute
local RTM_TABLE_MAX = (1 << 8 * fieldsize(rtnl.layout.rtmsg, "rtm_table")) - 1

local NEWROUTE, NEWLINK, NEWADDR = rtnl.rtm.NEWROUTE, rtnl.rtm.NEWLINK, rtnl.rtm.NEWADDR

local U32 = "=I4"

local function u32(value)
	return value and unpack(U32, value)
end

local function str(value)
	return value and unpack("z", value)
end

---
-- Creates a new rt object.
-- @function rt:new
-- @tparam[opt] table o an initial object table.
-- @treturn rt the new rt object.
-- @see class
local rt = session:new{proto = nl.proto.ROUTE}

---
-- Dumps all routes from the kernel routing tables.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of route tables.
function rt:route_dump(family)
	local header = rtmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0, 0, 0, 0, 0)
	local routes = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETROUTE, header)) do
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

---
-- Dumps all network interfaces from the kernel.
-- @treturn table list of link tables.
function rt:link_dump()
	local header = ifinfomsg:pack(sk.af.UNSPEC, 0, 0, 0, 0)
	local links = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETLINK, header)) do
		if msg.type == NEWLINK then
			local body = msg.body
			local fam, ltype, ifindex, flags, change = ifinfomsg:unpack(body)
			local attrs = message.attrs(body, IFINFO_LEN + 1)
			insert(links, {
				family = fam, ltype = ltype, ifindex = ifindex,
				flags = flags, change = change,
				name = str(attrs[rtnl.ifla.IFNAME]),
				mtu = u32(attrs[rtnl.ifla.MTU]),
			})
		end
	end
	return links
end

---
-- Dumps all interface addresses from the kernel.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of address tables.
function rt:addr_dump(family)
	local header = ifaddrmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0)
	local addrs = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETADDR, header)) do
		if msg.type == NEWADDR then
			local body = msg.body
			local fam, prefix_len, _, scope, ifindex = ifaddrmsg:unpack(body)
			local attrs = message.attrs(body, IFADDR_LEN + 1)
			insert(addrs, {
				family = fam, prefix_len = prefix_len, scope = scope, ifindex = ifindex,
				address = attrs[rtnl.ifa.ADDRESS] or attrs[rtnl.ifa.LOCAL],
				label = str(attrs[rtnl.ifa.LABEL]),
			})
		end
	end
	return addrs
end

local function route_attrs(opts)
	return message.attrs{
		[rtnl.rta.DST]     = opts.dst,
		[rtnl.rta.GATEWAY] = opts.gateway,
		[rtnl.rta.OIF]     = opts.oif,
		[rtnl.rta.TABLE]   = opts.table and opts.table > RTM_TABLE_MAX and opts.table or nil,
	}
end

---
-- Adds a route to the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `gateway`, `oif`, `table`, `protocol`, `scope`, `rtype`.
function rt:route_add(opts)
	local tbl = opts.table or rtnl.table.MAIN
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		tbl <= RTM_TABLE_MAX and tbl or rtnl.table.UNSPEC, opts.protocol or rtnl.rtprot.STATIC,
		opts.scope or rtnl.scope.UNIVERSE, opts.rtype or rtnl.rtn.UNICAST, 0)
	self:talk(NEWROUTE, nl.flag.CREATE | nl.flag.EXCL, header .. route_attrs(opts))
end

---
-- Deletes a route from the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `oif`, `table`.
function rt:route_del(opts)
	local tbl = opts.table or rtnl.table.MAIN
	-- scope NOWHERE is the deletion wildcard: match the route whatever its scope
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		tbl <= RTM_TABLE_MAX and tbl or rtnl.table.UNSPEC, 0, rtnl.scope.NOWHERE, 0, 0)
	self:talk(rtnl.rtm.DELROUTE, nil, header .. route_attrs(opts))
end

return rt

