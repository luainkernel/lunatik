--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink socket test (see socket.sh).

local socket = require("socket")
local sk     = require("linux.socket")
local nl     = require("linux.netlink")

local RTM_GETLINK   <const> = 18
local RTM_NEWLINK   <const> = 16
local NLM_F_REQUEST <const> = 0x01
local NLM_F_DUMP    <const> = 0x300
local NLMSG_HDRLEN  <const> = 16

local sock <close> = socket.new(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE)

-- bind + getsockname round-trip exercises the AF_NETLINK checkaddr/pushaddr paths
sock:bind(0, 0)
local pid, groups = sock:getsockname()
assert(type(pid) == "number" and groups == 0, "netlink getsockname round-trip failed")
print("netlink socket: getsockname ok")

-- a GETLINK dump exercises send (which attaches the kernel destination) + receive
local ifinfo = string.pack("<BBI2i4I4I4", 0, 0, 0, 0, 0, 0)
local hdr = string.pack("<I4I2I2I4I4", NLMSG_HDRLEN + #ifinfo, RTM_GETLINK,
	NLM_F_REQUEST | NLM_F_DUMP, 1, 0)
sock:send(hdr .. ifinfo)

local resp = sock:receive(8192)
assert(#resp >= NLMSG_HDRLEN, "no netlink response")
local _, rtype = string.unpack("<I4I2", resp)
assert(rtype == RTM_NEWLINK, "expected RTM_NEWLINK, got " .. rtype)
print("netlink socket: GETLINK round-trip ok")

