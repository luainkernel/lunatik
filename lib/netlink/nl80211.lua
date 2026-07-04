--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- nl80211 (wireless) interface. A `netlink.genl` specialization bound to the
-- `"nl80211"` generic netlink family: create an instance with `netlink.nl80211()`,
-- then list wiphys and interfaces over the socket. All methods block and require
-- a sleepable runtime.
--
-- @module netlink.nl80211
-- @see netlink.genl

local session = require("netlink.session")
local genl    = require("netlink.genl")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

local insert = table.insert
local u32, str = message.u32, message.str

local GET_WIPHY, GET_INTERFACE, NEW_INTERFACE =
	cmd.GET_WIPHY, cmd.GET_INTERFACE, cmd.NEW_INTERFACE

---
-- @type nl80211
local nl80211 = genl:new{}

---
-- Lists the wireless PHYs (wiphys) known to the kernel.
-- @treturn table list of `{wiphy, name}` tables.
function nl80211:wiphy_list()
	local byidx = {}
	for _, msg in ipairs(self:dump(self.id, GET_WIPHY)) do
		local idx = u32(msg.attrs[attr.WIPHY])
		if idx then
			-- GET_WIPHY replies are fragmented across messages per phy; the
			-- name arrives in only one of them, so accumulate by index
			local phy = byidx[idx] or {wiphy = idx}
			phy.name = phy.name or str(msg.attrs[attr.WIPHY_NAME])
			byidx[idx] = phy
		end
	end
	local phys = {}
	for _, phy in pairs(byidx) do insert(phys, phy) end
	return phys
end

---
-- Lists the wireless interfaces known to the kernel.
-- @treturn table list of `{ifindex, name, wiphy, iftype, mac}` tables (`mac`
--   is 6 raw bytes).
function nl80211:interface_list()
	local ifaces = {}
	for _, msg in ipairs(self:dump(self.id, GET_INTERFACE)) do
		if msg.cmd == NEW_INTERFACE then
			local a = msg.attrs
			insert(ifaces, {
				ifindex = u32(a[attr.IFINDEX]),
				name    = str(a[attr.IFNAME]),
				wiphy   = u32(a[attr.WIPHY]),
				iftype  = u32(a[attr.IFTYPE]),
				mac     = a[attr.MAC],
			})
		end
	end
	return ifaces
end

-- netlink.nl80211() builds the genl socket (via session) and caches the family id.
function nl80211:__call()
	local o = session.__call(self)
	o.id = o:family("nl80211")
	return o
end

-- genl is a second-level base, so unlike rt/genl the __call must be wired here
return setmetatable(nl80211, {__index = genl, __call = nl80211.__call})

