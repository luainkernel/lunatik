--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Wireless PHY (wiphy) listing. An `nl80211` object over the `"nl80211"`
-- generic netlink family: create an instance with `netlink.nl80211.wiphy()`
-- and list the radios; the underlying socket is closed by `close()` (or the
-- to-be-closed `__close`). All methods block and require a sleepable runtime.
--
-- @module netlink.nl80211.wiphy
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

local insert = table.insert
local u32, str = message.u32, message.str

---
-- @type wiphy

---
-- Creates a new wiphy object.
-- @function wiphy:new
-- @tparam[opt] table o an initial object table.
-- @treturn wiphy the new wiphy object.
-- @see class
local wiphy = object:new{GET = cmd.GET_WIPHY, NEW = cmd.NEW_WIPHY}

---
-- Lists the wireless PHYs (wiphys) known to the kernel.
-- @treturn table list of `{wiphy, name}` tables.
function wiphy:list()
	local byidx = {}
	for _, msg in ipairs(self:dump(self.id, self.GET)) do
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

return wiphy

