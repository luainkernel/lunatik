--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The nl80211 (wireless) namespace. Groups the nl80211 object classes, each a
-- `netlink.genl` session bound to the `"nl80211"` family.
-- @module netlink.nl80211

local wiphy     = require("netlink.nl80211.wiphy")
local interface = require("netlink.nl80211.interface")
local ap        = require("netlink.nl80211.ap")
local station   = require("netlink.nl80211.station")

local nl80211 = {}

---
-- Wireless PHY (wiphy) class.
-- Open sessions using `netlink.nl80211.wiphy()`.
-- @table netlink.nl80211.wiphy
-- @see netlink.nl80211.wiphy
nl80211.wiphy = wiphy

---
-- Wireless interface class.
-- Open sessions using `netlink.nl80211.interface()`.
-- @table netlink.nl80211.interface
-- @see netlink.nl80211.interface
nl80211.interface = interface

---
-- Access Point control class.
-- Open sessions using `netlink.nl80211.ap()`.
-- @table netlink.nl80211.ap
-- @see netlink.nl80211.ap
nl80211.ap = ap

---
-- Station management class.
-- Open sessions using `netlink.nl80211.station()`.
-- @table netlink.nl80211.station
-- @see netlink.nl80211.station
nl80211.station = station

return nl80211

