--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The netlink namespace. Groups the netlink factories.
-- @module netlink

local rt      = require("netlink.rt")
local genl    = require("netlink.genl")
local nl80211 = require("netlink.nl80211")

local netlink = {}

---
-- The rtnetlink namespace; groups the `NETLINK_ROUTE` object classes.
-- @table netlink.rt
-- @see netlink.rt
netlink.rt = rt

---
-- Generic netlink session specialization.
-- Open sessions (sleepable) using `netlink.genl()`.
-- @table netlink.genl
-- @see netlink.genl
netlink.genl = genl

---
-- The nl80211 (wireless) namespace; groups the nl80211 object classes.
-- @table netlink.nl80211
-- @see netlink.nl80211
netlink.nl80211 = nl80211

return netlink

