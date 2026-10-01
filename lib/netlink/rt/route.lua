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
-- @see netlink.rt.object
-- @see netlink.session
--

local object  = require("netlink.rt.object")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local u32 = message.u32

local rtmsg     = struct(rtnl.layout.rtmsg)
local RTMSG_LEN = rtmsg.size

---
-- @type route

---
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.rt.route()`.
-- @function route:new
-- @tparam[opt] table o an initial object table.
-- @treturn route the wrapped table or the derived class.
-- @see class
local route = object:new{
	GET = rtnl.rtm.GETROUTE, NEW = rtnl.rtm.NEWROUTE, DEL = rtnl.rtm.DELROUTE,
	TABLE_MAX = object.tablemax(rtmsg, "rtm_table"),
}

function route:header(family)
	return rtmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0, 0, 0, 0, 0)
end

function route:decode(body)
	local fam, dst_len, src_len, tos, tbl, protocol, scope, rtype, flags = rtmsg:unpack(body)
	local attrs = message.attrs(body, RTMSG_LEN + 1)
	return {
		family = fam, dst_len = dst_len, src_len = src_len, tos = tos,
		table = u32(attrs[rtnl.rta.TABLE]) or tbl,
		protocol = protocol, scope = scope, rtype = rtype, flags = flags,
		dst = attrs[rtnl.rta.DST], gateway = attrs[rtnl.rta.GATEWAY],
		oif = u32(attrs[rtnl.rta.OIF]),
		priority = u32(attrs[rtnl.rta.PRIORITY]),
	}
end

---
-- Opens a session, calling the class: `netlink.rt.route([pid])`.
-- @function route:__call
-- @tparam[opt] integer pid a task whose network namespace the session talks to, as `socket.new`
--   takes it; the initial network namespace when absent.
-- @treturn route a new route object.
-- @raise `ESRCH` if no task has that pid, or `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own.
-- @see netlink.session

---
-- Lists all routes from the kernel routing tables.
-- @function route:list
-- @tparam[opt] table opts list options: `family`, the address family of the records listed
--   (default `AF_UNSPEC`, every family).
-- @treturn table list of route tables, each with `family`, `dst_len`, `src_len`, `tos`, `table`,
--   `protocol`, `scope`, `rtype`, `flags`, `dst`, `gateway`, `oif` and `priority`; `dst` and
--   `gateway` are the address bytes in network byte order; `table` is the header's when the reply
--   lacks the `TABLE` attribute, and any other field whose attribute the reply lacks is nil.

local function route_attrs(route, opts)
	return message.attrs{
		[rtnl.rta.DST]     = opts.dst,
		[rtnl.rta.GATEWAY] = opts.gateway,
		[rtnl.rta.OIF]     = opts.oif,
		[rtnl.rta.TABLE]   = route:attrtable(opts.table),
	}
end

---
-- Adds a route to the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `gateway`, `oif`, `table`, `protocol`, `scope`, `rtype`. `dst` and
--   `gateway` are the address bytes in network byte order, e.g.
--   `string.pack(">I4", net.aton("192.0.2.0"))`, never an integer.
-- @raise the name of the errno a netlink error reply carries, `EEXIST` when the route exists.
function route:add(opts)
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		self:headertable(opts.table or rtnl.table.MAIN), opts.protocol or rtnl.rtprot.STATIC,
		opts.scope or rtnl.scope.UNIVERSE, opts.rtype or rtnl.rtn.UNICAST, 0)
	self:talk(self.NEW, header .. route_attrs(self, opts), nl.flag.CREATE | nl.flag.EXCL)
end

---
-- Deletes a route from the kernel routing table.
-- @tparam table opts route parameters: optional `family` (default `AF_INET`),
--   `dst_len`, `dst`, `oif`, `table`, as `add` takes them.
-- @raise the name of the errno a netlink error reply carries, `ESRCH` when no route matches.
function route:del(opts)
	-- scope NOWHERE is the deletion wildcard: match the route whatever its scope
	local header = rtmsg:pack(opts.family or sk.af.INET, opts.dst_len or 0, 0, 0,
		self:headertable(opts.table or rtnl.table.MAIN), 0, rtnl.scope.NOWHERE, 0, 0)
	self:talk(self.DEL, header .. route_attrs(self, opts))
end

return route

