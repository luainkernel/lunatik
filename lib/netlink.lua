--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The netlink namespace. Groups the netlink factories.
-- @module netlink

local channel = require("netlink.channel")
local rt      = require("netlink.rt")
local genl    = require("netlink.genl")

local netlink = {}

---
-- Registers a generic netlink family with one multicast group; the returned
-- channel's `multicast`/`unicast` are softirq-safe.
-- @function netlink.channel
-- @tparam string name Generic netlink family name (up to `GENL_NAMSIZ-1` bytes).
-- @treturn netlink.channel A new channel object.
-- @see netlink.channel
netlink.channel = channel.new

---
-- rtnetlink session specialization for routes, links and addresses.
-- Open sessions (sleepable) using `netlink.rt()`.
-- @table netlink.rt
-- @see netlink.rt
netlink.rt = rt

---
-- Generic netlink session specialization.
-- Open sessions (sleepable) using `netlink.genl()`.
-- @table netlink.genl
-- @see netlink.genl
netlink.genl = genl

return netlink

