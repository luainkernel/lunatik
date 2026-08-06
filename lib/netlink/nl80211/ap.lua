--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Access Point control. An `nl80211` object over the `"nl80211"` generic
-- netlink family: create an instance with `netlink.nl80211.ap()` then start and
-- stop beaconing on an AP-mode interface; the underlying socket is closed by
-- `close()` (or the to-be-closed `__close`). All methods block and require a
-- sleepable runtime.
--
-- @module netlink.nl80211.ap
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

---
-- @type ap

---
-- Creates a new ap object.
-- @function ap:new
-- @tparam[opt] table o an initial object table.
-- @treturn ap the new ap object.
-- @see class
local ap = object:new{START = cmd.START_AP, STOP = cmd.STOP_AP}

---
-- Starts beaconing on an AP-mode interface (which must already be up).
-- @tparam table opts AP parameters: `ifindex` (an AP interface), `freq`
--   (channel frequency in MHz), `beacon_interval`, `dtim` and `head` (the raw
--   beacon frame up to the TIM element); optional `ssid` and `tail` (the raw
--   beacon frame after the TIM).
-- @raise on a netlink error (e.g. the interface is not an AP, is down, or the
--   beacon or channel is rejected).
function ap:start(opts)
	self:call(self.id, self.START, 0, message.attrs{
		[attr.IFINDEX]         = opts.ifindex,
		[attr.WIPHY_FREQ]      = opts.freq,
		[attr.BEACON_INTERVAL] = opts.beacon_interval,
		[attr.DTIM_PERIOD]     = opts.dtim,
		[attr.SSID]            = opts.ssid,
		[attr.BEACON_HEAD]     = opts.head,
		[attr.BEACON_TAIL]     = opts.tail,
	})
end

---
-- Stops beaconing on an AP-mode interface.
-- @tparam table opts AP parameters: `ifindex`.
-- @raise on a netlink error.
function ap:stop(opts)
	self:call(self.id, self.STOP, 0, message.attrs{[attr.IFINDEX] = opts.ifindex})
end

return ap

