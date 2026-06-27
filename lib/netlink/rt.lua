--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- rtnetlink interface for routes, links and addresses.
-- Create an instance with `rt()` and call its methods; the underlying socket is
-- closed by `close()` (or the to-be-closed `__close`). All methods block and
-- require a sleepable runtime.
--
-- @module netlink.rt
-- @see netlink
--

local netlink = require("netlink")
local message = require("netlink.message")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local af   = require("linux.socket").af

-- struct rtmsg: family,dst_len,src_len,tos,table,protocol,scope,type (u8) flags(u32)
local RTMSG     = "<BBBBBBBBI4"
local RTMSG_LEN = 12
-- struct ifinfomsg: family(u8) pad(u8) type(u16) ifindex(i32) flags(u32) change(u32)
local IFINFO     = "<BBI2i4I4I4"
local IFINFO_LEN = 16
-- struct ifaddrmsg: family(u8) prefixlen(u8) flags(u8) scope(u8) ifindex(u32)
local IFADDR     = "<BBBBI4"
local IFADDR_LEN = 8

local U32 = "<I4"

local function u32(value)
	return value and string.unpack(U32, value)
end

local function str(value)
	return value and string.unpack("z", value)
end

local rt = {}

---
-- Constructor; sets up the metatable for OOP-style method dispatch.
-- @tparam[opt] table o initial object table.
-- @treturn table the new rt object.
function rt:new(o)
	o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

---
-- Creates a new rtnetlink instance backed by a `NETLINK_ROUTE` socket.
-- @treturn table a new rt object.
function rt:__call()
	local o = self:new()
	o.socket = netlink.new(nl.proto.ROUTE)
	return o
end

---
-- Closes the underlying socket.
function rt:close()
	self.socket:close()
end

---
-- Sends a dump request and returns the parsed response messages.
-- @tparam integer mtype RTM_* message type.
-- @tparam string header the family header.
-- @treturn table list of parsed messages.
function rt:dump(mtype, header)
	self.socket:send(message.encode(mtype, nl.flag.REQUEST | nl.flag.DUMP, message.seq(), header))
	local buf = message.recv_all(self.socket)
	message.check_error(buf)
	return message.parse(buf)
end

---
-- Dumps all routes from the kernel routing tables.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of route tables.
function rt:route_dump(family)
	local header = string.pack(RTMSG, family or af.UNSPEC, 0, 0, 0, 0, 0, 0, 0, 0)
	local routes = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETROUTE, header)) do
		if msg.type == rtnl.rtm.NEWROUTE then
			local body = msg.body
			local fam, dst_len, src_len, tos, tbl, protocol, scope, rtype, flags =
				string.unpack(RTMSG, body)
			local attrs = message.attrs(body, RTMSG_LEN + 1)
			table.insert(routes, {
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
	local header = string.pack(IFINFO, af.UNSPEC, 0, 0, 0, 0, 0)
	local links = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETLINK, header)) do
		if msg.type == rtnl.rtm.NEWLINK then
			local body = msg.body
			local fam, _, ltype, ifindex, flags, change = string.unpack(IFINFO, body)
			local attrs = message.attrs(body, IFINFO_LEN + 1)
			table.insert(links, {
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
	local header = string.pack(IFADDR, family or af.UNSPEC, 0, 0, 0, 0)
	local addrs = {}
	for _, msg in ipairs(self:dump(rtnl.rtm.GETADDR, header)) do
		if msg.type == rtnl.rtm.NEWADDR then
			local body = msg.body
			local fam, prefix_len, _, scope, ifindex = string.unpack(IFADDR, body)
			local attrs = message.attrs(body, IFADDR_LEN + 1)
			table.insert(addrs, {
				family = fam, prefix_len = prefix_len, scope = scope, ifindex = ifindex,
				address = attrs[rtnl.ifa.ADDRESS] or attrs[rtnl.ifa.LOCAL],
				label = str(attrs[rtnl.ifa.LABEL]),
			})
		end
	end
	return addrs
end

---
-- Sends a route request and checks the kernel acknowledgment.
-- @tparam integer mtype RTM_* message type.
-- @tparam integer flags NLM_F_* flags.
-- @tparam string payload the rtmsg header and attributes.
function rt:route(mtype, flags, payload)
	self.socket:send(message.encode(mtype, flags, message.seq(), payload))
	message.check_error(self.socket:recv(message.BUFSIZE))
end

local function route_attrs(opts)
	local attrs = ""
	if opts.dst then attrs = attrs .. message.attr(rtnl.rta.DST, opts.dst) end
	if opts.gateway then attrs = attrs .. message.attr(rtnl.rta.GATEWAY, opts.gateway) end
	if opts.oif then attrs = attrs .. message.attr_u32(rtnl.rta.OIF, opts.oif) end
	return attrs
end

---
-- Adds a route to the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `gateway`, `oif`, `table`, `protocol`, `scope`, `rtype`.
function rt:route_add(opts)
	local header = string.pack(RTMSG, opts.family or af.INET, opts.dst_len or 0, 0, 0,
		opts.table or rtnl.table.MAIN, opts.protocol or rtnl.rtprot.STATIC,
		opts.scope or rtnl.scope.UNIVERSE, opts.rtype or rtnl.rtn.UNICAST, 0)
	self:route(rtnl.rtm.NEWROUTE,
		nl.flag.REQUEST | nl.flag.ACK | nl.flag.CREATE | nl.flag.EXCL,
		header .. route_attrs(opts))
end

---
-- Deletes a route from the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `oif`, `table`.
function rt:route_del(opts)
	-- scope NOWHERE is the deletion wildcard: match the route whatever its scope
	local header = string.pack(RTMSG, opts.family or af.INET, opts.dst_len or 0, 0, 0,
		opts.table or rtnl.table.MAIN, 0, rtnl.scope.NOWHERE, 0, 0)
	self:route(rtnl.rtm.DELROUTE, nl.flag.REQUEST | nl.flag.ACK, header .. route_attrs(opts))
end

return setmetatable(rt, rt)

