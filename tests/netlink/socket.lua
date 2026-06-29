--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink socket test (see socket.sh).
-- Exercises the raw netlink socket (new/send/recv/close) with a hand-built
-- RTM_GETLINK dump request; the rtnetlink helpers arrive in a later module.

local netlink = require("netlink")
local nl = require("linux.netlink")

local RTM_GETLINK <const> = 18
local NLMSG_HDRLEN <const> = 16
local IFINFO <const> = "<BBI2i4I4I4"
local IFINFO_LEN <const> = 16

local s <close> = netlink.new(nl.proto.ROUTE)
local header = string.pack("<I4I2I2I4I4", NLMSG_HDRLEN + IFINFO_LEN, RTM_GETLINK,
	nl.flag.REQUEST | nl.flag.DUMP, 1, 0)
local ifinfomsg = string.pack(IFINFO, 0, 0, 0, 0, 0, 0)

s:send(header .. ifinfomsg)
local reply = s:recv(8192)
assert(#reply > 0, "expected a netlink reply")
print("netlink socket: round-trip ok")

