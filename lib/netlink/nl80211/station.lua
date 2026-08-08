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
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd     = require("linux.nl80211").cmd
local attr    = require("linux.nl80211").attr
local staflag = require("linux.nl80211").staflag

local pack = string.pack

-- STA_FLAGS2 carries bit positions from the station-flag enum (§ NL80211_STA_FLAG_)
local AUTHORIZED = 1 << staflag.AUTHORIZED

---
-- @type station

---
-- Creates a new station object.
-- @function station:new
-- @tparam[opt] table o an initial object table.
-- @treturn station the new station object.
-- @see class
local station = object:new{
	GET = cmd.GET_STATION, NEW = cmd.NEW_STATION,
	DEL = cmd.DEL_STATION, SET = cmd.SET_STATION,
}

function station:decode(attrs)
	return { mac = attrs[attr.MAC] }
end

---
-- Lists the stations of an AP interface.
-- @tparam integer ifindex the AP interface index.
-- @treturn table list of `{mac}` tables.
function station:list(ifindex)
	return object.list(self, message.attrs{[attr.IFINDEX] = ifindex})
end

---
-- Adds a station to an AP interface.
-- @tparam table opts station parameters: `ifindex`, `mac`, `aid`,
--   `listen_interval` and `supported_rates` (raw rate bytes).
-- @raise on a netlink error.
function station:add(opts)
	self:call(self.id, self.NEW, 0, message.attrs{
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
	self:call(self.id, self.SET, 0, message.attrs{
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
	self:call(self.id, self.DEL, 0, message.attrs{
		[attr.IFINDEX] = opts.ifindex,
		[attr.MAC]     = opts.mac,
	})
end

return station

