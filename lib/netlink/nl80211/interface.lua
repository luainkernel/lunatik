--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Wireless interface listing. An `nl80211` object over the `"nl80211"` generic
-- netlink family: create an instance with `netlink.nl80211.interface()` and
-- list the wireless interfaces; the underlying socket is closed by `close()`
-- (or the to-be-closed `__close`). All methods block and require a sleepable
-- runtime.
--
-- @module netlink.nl80211.interface
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

local u32, str = message.u32, message.str

---
-- @type interface

---
-- Creates a new interface object.
-- @function interface:new
-- @tparam[opt] table o an initial object table.
-- @treturn interface the new interface object.
-- @see class
local interface = object:new{GET = cmd.GET_INTERFACE, NEW = cmd.NEW_INTERFACE}

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

return interface

