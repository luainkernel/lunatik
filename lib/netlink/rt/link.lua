--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Network interface (link) listing. A `netlink.session` specialization over
-- the `NETLINK_ROUTE` protocol: create an instance with `netlink.rt.link()`
-- and list the kernel's interfaces; the underlying socket is closed by
-- `close()` (or the to-be-closed `__close`). All methods block and require a
-- sleepable runtime.
--
-- @module netlink.rt.link
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local insert = table.insert
local u32, str = message.u32, message.str

local ifinfomsg  = struct(rtnl.layout.ifinfomsg)
local IFINFO_LEN = ifinfomsg.size

local NEWLINK, GETLINK = rtnl.rtm.NEWLINK, rtnl.rtm.GETLINK

---
-- @type link

---
-- Creates a new link object.
-- @function link:new
-- @tparam[opt] table o an initial object table.
-- @treturn link the new link object.
-- @see class
local link = session:new{proto = nl.proto.ROUTE}

---
-- Lists all network interfaces from the kernel.
-- @treturn table list of link tables.
function link:list()
	local header = ifinfomsg:pack(sk.af.UNSPEC, 0, 0, 0, 0)
	local links = {}
	for _, msg in ipairs(self:dump(GETLINK, header)) do
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

return link

