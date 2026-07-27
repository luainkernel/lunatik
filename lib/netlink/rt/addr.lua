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
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")
local sk   = require("linux.socket")

local insert = table.insert
local str = message.str

local ifaddrmsg  = struct(rtnl.layout.ifaddrmsg)
local IFADDR_LEN = ifaddrmsg.size

local NEWADDR, GETADDR = rtnl.rtm.NEWADDR, rtnl.rtm.GETADDR

---
-- @type addr

---
-- Creates a new addr object.
-- @function addr:new
-- @tparam[opt] table o an initial object table.
-- @treturn addr the new addr object.
-- @see class
local addr = session:new{proto = nl.proto.ROUTE}

---
-- Lists all interface addresses from the kernel.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of address tables.
function addr:list(family)
	local header = ifaddrmsg:pack(family or sk.af.UNSPEC, 0, 0, 0, 0)
	local addrs = {}
	for _, msg in ipairs(self:dump(GETADDR, header)) do
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

return addr

