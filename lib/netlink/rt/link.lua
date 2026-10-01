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
-- @see netlink.session
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
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.rt.link()`.
-- @function link:new
-- @tparam[opt] table o an initial object table.
-- @treturn link the wrapped table or the derived class.
-- @see class
local link = object:new{
	GET = rtnl.rtm.GETLINK, NEW = rtnl.rtm.NEWLINK, SET = rtnl.rtm.SETLINK,
}

function link:header()
	return ifinfomsg:pack(sk.af.UNSPEC, 0, 0, 0, 0)
end

function link:decode(body)
	local fam, ltype, ifindex, flags, change = ifinfomsg:unpack(body)
	local attrs = message.parseattrs(body, IFINFO_LEN + 1)
	return {
		family = fam, type = ltype, ifindex = ifindex,
		flags = flags, change = change,
		name = str(attrs[rtnl.ifla.IFNAME]),
		mtu = u32(attrs[rtnl.ifla.MTU]),
	}
end

---
-- Opens a session, calling the class: `netlink.rt.link([pid])`.
-- @function link:__call
-- @tparam[opt] integer pid a task whose network namespace the session talks to, as `socket.new`
--   takes it; the initial network namespace when absent.
-- @treturn link a new link object.
-- @raise `ESRCH` if no task has that pid, or `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own.
-- @see netlink.session

---
-- Lists all network interfaces from the kernel.
-- @function link:list
-- @tparam[opt] table opts list options, of which a link takes none.
-- @treturn table list of link tables, each with `family`, `type`, `ifindex`, `flags`, `change`,
--   `name` and `mtu`; a field whose attribute the reply lacks is nil.

---
-- Sets an interface's administrative up state.
-- @tparam table opts link parameters: `ifindex` and `up` (boolean).
-- @raise on a netlink error.
function link:set(opts)
	local flags = opts.up and rtnl.iff.UP or 0
	self:talk(self.SET, ifinfomsg:pack(sk.af.UNSPEC, 0, opts.ifindex, flags, rtnl.iff.UP))
end

return link

