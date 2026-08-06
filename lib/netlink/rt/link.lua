--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Network interface (link) management. A `netlink.session` specialization over
-- the `NETLINK_ROUTE` protocol: create an instance with `netlink.rt.link()`
-- to list the kernel's interfaces and set their up state; the underlying
-- socket is closed by `close()` (or the to-be-closed `__close`). All methods
-- block and require a sleepable runtime.
--
-- @module netlink.rt.link
-- @see netlink.rt.object
--

local object  = require("netlink.rt.object")
local message = require("netlink.message")
local struct  = require("struct")

local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local u32, str = message.u32, message.str

local ifinfomsg  = struct(rtnl.layout.ifinfomsg)
local IFINFO_LEN = ifinfomsg.size

---
-- @type link

---
-- Creates a new link object.
-- @function link:new
-- @tparam[opt] table o an initial object table.
-- @treturn link the new link object.
-- @see class
local link = object:new{
	GET = rtnl.rtm.GETLINK, NEW = rtnl.rtm.NEWLINK, SET = rtnl.rtm.SETLINK,
}

function link:header()
	return ifinfomsg:pack(sk.af.UNSPEC, 0, 0, 0, 0)
end

function link:decode(body)
	local fam, ltype, ifindex, flags, change = ifinfomsg:unpack(body)
	local attrs = message.attrs(body, IFINFO_LEN + 1)
	return {
		family = fam, ltype = ltype, ifindex = ifindex,
		flags = flags, change = change,
		name = str(attrs[rtnl.ifla.IFNAME]),
		mtu = u32(attrs[rtnl.ifla.MTU]),
	}
end

---
-- Lists all network interfaces from the kernel.
-- @function link:list
-- @treturn table list of link tables.

---
-- Sets an interface's administrative up state.
-- @tparam table opts link parameters: `ifindex` and `up` (boolean).
-- @raise on a netlink error.
function link:set(opts)
	local flags = opts.up and rtnl.iff.UP or 0
	self:talk(self.SET, nil, ifinfomsg:pack(sk.af.UNSPEC, 0, opts.ifindex, flags, rtnl.iff.UP))
end

return link

