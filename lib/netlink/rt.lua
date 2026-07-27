--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The rtnetlink namespace. Groups the `NETLINK_ROUTE` object classes; each
-- opens its own request/response session (sleepable).
-- @module netlink.rt

local route = require("netlink.rt.route")
local link  = require("netlink.rt.link")
local addr  = require("netlink.rt.addr")

local rt = {}

---
-- Kernel routing table class.
-- Open sessions using `netlink.rt.route()`.
-- @table netlink.rt.route
-- @see netlink.rt.route
rt.route = route

---
-- Network interface (link) class.
-- Open sessions using `netlink.rt.link()`.
-- @table netlink.rt.link
-- @see netlink.rt.link
rt.link = link

---
-- Interface address class.
-- Open sessions using `netlink.rt.addr()`.
-- @table netlink.rt.addr
-- @see netlink.rt.addr
rt.addr = addr

return rt

