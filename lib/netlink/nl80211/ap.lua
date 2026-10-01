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
-- @see netlink.session
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local nl80211 = require("linux.nl80211")
local cmd     = nl80211.cmd
local attr    = nl80211.attr

---
-- @type ap

---
-- Wraps a table in the class, or derives a class from it. It opens no socket: calling the class
-- does, `netlink.nl80211.ap()`.
-- @function ap:new
-- @tparam[opt] table o an initial object table.
-- @treturn ap the wrapped table or the derived class.
-- @see class
local ap = object:new{START = cmd.START_AP, STOP = cmd.STOP_AP}

---
-- Opens a session, calling the class: `netlink.nl80211.ap([pid])`.
-- @function ap:__call
-- @tparam[opt] integer pid a task whose network namespace the object reaches, which holds the wiphys
--   and interfaces nl80211 answers for; the initial network namespace when absent.
-- @treturn ap a new ap object.
-- @raise `ESRCH` if no task has that pid, `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own, or `ENOENT` when the nl80211 family is not registered.
-- @see netlink.session

---
-- Starts beaconing on an AP-mode interface (which must already be up).
-- @tparam table opts AP parameters: `ifindex` (an AP interface), `freq`
--   (channel frequency in MHz), `beacon_interval`, `dtim` and `head` (the raw
--   beacon frame up to the TIM element); optional `ssid` and `tail` (the raw
--   beacon frame after the TIM).
-- @raise on a netlink error (e.g. the interface is not an AP, is down, or the
--   beacon or channel is rejected).
function ap:start(opts)
	self:talk(self.id, self.START, message.attrs{
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
	self:talk(self.id, self.STOP, message.attrs{[attr.IFINDEX] = opts.ifindex})
end

return ap

