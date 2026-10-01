--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Interface address listing. A `netlink.session` specialization over the
-- `NETLINK_ROUTE` protocol: create an instance with `netlink.rt.addr()` and
-- list the kernel's interface addresses; the underlying socket is closed by
-- `close()` (or the to-be-closed `__close`). All methods block and require a
-- sleepable runtime.
--
-- @module netlink.rt.addr
-- @see netlink.rt.object
-- @see netlink.session
--

local object  = require("netlink.rt.object")
local message = require("netlink.message")
local struct  = require("struct")

local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local str = message.str

local ifaddrmsg  = struct(rtnl.layout.ifaddrmsg)
local IFADDR_LEN = ifaddrmsg.size

---
-- @type addr

---
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.rt.addr()`.
-- @function addr:new
-- @tparam[opt] table o an initial object table.
-- @treturn addr the wrapped table or the derived class.
-- @see class
local addr = object:new{GET = rtnl.rtm.GETADDR, NEW = rtnl.rtm.NEWADDR}

function addr:header(family)
	return ifaddrmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0)
end

function addr:decode(body)
	local fam, prefixlen, _, scope, ifindex = ifaddrmsg:unpack(body)
	local attrs = message.attrs(body, IFADDR_LEN + 1)
	local peer = attrs[rtnl.ifa.ADDRESS]
	local address = attrs[rtnl.ifa.LOCAL] or peer
	return {
		family = fam, prefixlen = prefixlen, scope = scope, ifindex = ifindex,
		address = address, peer = peer ~= address and peer or nil,
		label = str(attrs[rtnl.ifa.LABEL]),
	}
end

---
-- Opens a session, calling the class: `netlink.rt.addr([pid])`.
-- @function addr:__call
-- @tparam[opt] integer pid a task whose network namespace the session talks to, as `socket.new`
--   takes it; the initial network namespace when absent.
-- @treturn addr a new addr object.
-- @raise `ESRCH` if no task has that pid, or `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own.
-- @see netlink.session

---
-- Lists all interface addresses from the kernel.
-- @function addr:list
-- @tparam[opt] table opts list options: `family`, the address family of the records listed
--   (default `AF_UNSPEC`, every family).
-- @treturn table list of address tables, each with `family`, `prefixlen`, `scope`, `ifindex`,
--   `address`, `peer` and `label`; `address` is the interface's own address and `peer`, only on an
--   address configured with one, the other end of a point-to-point link, both as bytes in network
--   byte order; a field whose attribute the reply lacks is nil.

return addr

