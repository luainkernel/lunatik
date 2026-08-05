--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Wireless interface management. An `nl80211` object over the `"nl80211"`
-- generic netlink family: create an instance with `netlink.nl80211.interface()`
-- then list, add and delete wireless interfaces; the underlying socket is
-- closed by `close()` (or the to-be-closed `__close`). All methods block and
-- require a sleepable runtime.
--
-- @module netlink.nl80211.interface
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

local pack = string.pack
local u32, str = message.u32, message.str

---
-- @type interface

---
-- Creates a new interface object.
-- @function interface:new
-- @tparam[opt] table o an initial object table.
-- @treturn interface the new interface object.
-- @see class
local interface = object:new{
	GET = cmd.GET_INTERFACE, NEW = cmd.NEW_INTERFACE, DEL = cmd.DEL_INTERFACE,
}

function interface:decode(attrs)
	return {
		ifindex = u32(attrs[attr.IFINDEX]),
		name    = str(attrs[attr.IFNAME]),
		wiphy   = u32(attrs[attr.WIPHY]),
		iftype  = u32(attrs[attr.IFTYPE]),
		mac     = attrs[attr.MAC],
	}
end

---
-- Lists the wireless interfaces known to the kernel.
-- @function interface:list
-- @treturn table list of `{ifindex, name, wiphy, iftype, mac}` tables (`mac`
--   is 6 raw bytes).

---
-- Adds a virtual interface to a wiphy.
-- @tparam table opts interface parameters: `wiphy` (radio index, from
--   `netlink.nl80211.wiphy`), `name` and `iftype` (an `nl80211.iftype`).
-- @treturn integer the new interface's `ifindex`.
-- @raise on a netlink error (e.g. the name is taken or the iftype unsupported).
function interface:add(opts)
	for _, msg in ipairs(self:call(self.id, self.NEW, 0, message.attrs{
		[attr.WIPHY]  = opts.wiphy,
		[attr.IFNAME] = pack("z", opts.name),
		[attr.IFTYPE] = opts.iftype,
	})) do
		local ifindex = u32(msg.attrs[attr.IFINDEX])
		if ifindex then return ifindex end
	end
end

---
-- Deletes a virtual interface.
-- @tparam table opts interface parameters: `ifindex`.
-- @raise on a netlink error.
function interface:del(opts)
	self:call(self.id, self.DEL, 0, message.attrs{[attr.IFINDEX] = opts.ifindex})
end

return interface

