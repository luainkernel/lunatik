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
-- @see netlink.session
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local nl80211 = require("linux.nl80211")
local cmd     = nl80211.cmd
local attr    = nl80211.attr

local insert, sort = table.insert, table.sort
local u32, str = message.u32, message.str

---
-- @type wiphy

---
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.nl80211.wiphy()`.
-- @function wiphy:new
-- @tparam[opt] table o an initial object table.
-- @treturn wiphy the wrapped table or the derived class.
-- @see class
local wiphy = object:new{GET = cmd.GET_WIPHY, NEW = cmd.NEW_WIPHY}

local function byindex(a, b)
	return a.wiphy < b.wiphy
end

---
-- Opens a session, calling the class: `netlink.nl80211.wiphy([pid])`.
-- @function wiphy:__call
-- @tparam[opt] integer pid a task whose network namespace the object reaches, which holds the wiphys
--   and interfaces nl80211 answers for; the initial network namespace when absent.
-- @treturn wiphy a new wiphy object; `nil` and `"ESRCH"` if no task has that pid, or the task
--   has exited.
-- @raise `EOPNOTSUPP` on a kernel whose sockets cannot hold a namespace of their own, or `ENOENT`
--   when the nl80211 family is not registered.
-- @see netlink.session

---
-- Lists the wireless PHYs (wiphys) known to the kernel.
-- @tparam[opt] table opts list options, of which a wiphy takes none.
-- @treturn table list of `{wiphy, name}` tables, in wiphy index order.
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
	sort(phys, byindex)
	return phys
end

return wiphy

