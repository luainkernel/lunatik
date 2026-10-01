--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Station management. An `nl80211` object over the `"nl80211"` generic netlink
-- family: create an instance with `netlink.nl80211.station()` then add, delete,
-- authorize and list the stations of an AP interface; the underlying socket is
-- closed by `close()` (or the to-be-closed `__close`). All methods block and
-- require a sleepable runtime.
--
-- @module netlink.nl80211.station
-- @see netlink.session
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local nl80211  = require("linux.nl80211")
local cmd      = nl80211.cmd
local attr     = nl80211.attr
local sta_flag = nl80211.sta_flag

local pack = string.pack

-- STA_FLAGS2 carries bit positions from the station-flag enum (§ NL80211_STA_FLAG_)
local AUTHORIZED = 1 << sta_flag.AUTHORIZED

---
-- @type station

---
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.nl80211.station()`.
-- @function station:new
-- @tparam[opt] table o an initial object table.
-- @treturn station the wrapped table or the derived class.
-- @see class
local station = object:new{
	GET = cmd.GET_STATION, NEW = cmd.NEW_STATION,
	DEL = cmd.DEL_STATION, SET = cmd.SET_STATION,
}

function station:decode(attrs)
	return { mac = attrs[attr.MAC] }
end

function station:filter(opts)
	return message.attrs{[attr.IFINDEX] = opts.ifindex}
end

---
-- Opens a session, calling the class: `netlink.nl80211.station([pid])`.
-- @function station:__call
-- @tparam[opt] integer pid a task whose network namespace the object reaches, which holds the wiphys
--   and interfaces nl80211 answers for; the initial network namespace when absent.
-- @treturn station a new station object.
-- @raise `ESRCH` if no task has that pid, `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own, or `ENOENT` when the nl80211 family is not registered.
-- @see netlink.session

---
-- Lists the stations of an AP interface.
-- @function station:list
-- @tparam table opts list options: `ifindex`, the AP interface.
-- @treturn table list of `{mac}` tables.

---
-- Adds a station to an AP interface.
-- @tparam table opts station parameters: `ifindex`, `mac`, `aid`,
--   `listen_interval` and `supported_rates` (raw rate bytes).
-- @raise on a netlink error.
function station:add(opts)
	self:talk(self.id, self.NEW, message.attrs{
		[attr.IFINDEX]             = opts.ifindex,
		[attr.MAC]                 = opts.mac,
		[attr.STA_AID]             = pack("=I2", opts.aid),
		[attr.STA_LISTEN_INTERVAL] = pack("=I2", opts.listen_interval),
		[attr.STA_SUPPORTED_RATES] = opts.supported_rates,
	})
end

---
-- Sets a station's authorized state, opening or closing its controlled port.
-- @tparam table opts station parameters: `ifindex`, `mac` and `authorized`.
-- @raise on a netlink error.
function station:set(opts)
	self:talk(self.id, self.SET, message.attrs{
		[attr.IFINDEX]    = opts.ifindex,
		[attr.MAC]        = opts.mac,
		[attr.STA_FLAGS2] = pack("=I4I4", AUTHORIZED, opts.authorized and AUTHORIZED or 0),
	})
end

---
-- Removes a station from an AP interface.
-- @tparam table opts station parameters: `ifindex` and `mac`.
-- @raise on a netlink error.
function station:del(opts)
	self:talk(self.id, self.DEL, message.attrs{
		[attr.IFINDEX] = opts.ifindex,
		[attr.MAC]     = opts.mac,
	})
end

return station

