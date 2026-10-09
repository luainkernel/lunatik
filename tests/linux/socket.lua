--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.socket test (see run.sh).
--

local sk    = require("linux.socket")
local test  = require("tests.lib").test
local check = require("tests.linux.check")

-- the IP_ options net/ipv4/ip_sockglue.c takes, at the values uapi/linux/in.h gives them
local options = {
	TOS = 1, TTL = 2, HDRINCL = 3, OPTIONS = 4, ROUTER_ALERT = 5, RECVOPTS = 6, RETOPTS = 7, PKTINFO = 8,
	PKTOPTIONS = 9, MTU_DISCOVER = 10, RECVERR = 11, RECVTTL = 12, RECVTOS = 13, MTU = 14, FREEBIND = 15,
	IPSEC_POLICY = 16, XFRM_POLICY = 17, PASSSEC = 18, TRANSPARENT = 19, RECVORIGDSTADDR = 20, MINTTL = 21,
	NODEFRAG = 22, CHECKSUM = 23, BIND_ADDRESS_NO_PORT = 24, RECVFRAGSIZE = 25, RECVERR_RFC4884 = 26,
	MULTICAST_IF = 32, MULTICAST_TTL = 33, MULTICAST_LOOP = 34, ADD_MEMBERSHIP = 35, DROP_MEMBERSHIP = 36,
	UNBLOCK_SOURCE = 37, BLOCK_SOURCE = 38, ADD_SOURCE_MEMBERSHIP = 39, DROP_SOURCE_MEMBERSHIP = 40,
	MSFILTER = 41, MULTICAST_ALL = 49, UNICAST_IF = 50, LOCAL_PORT_RANGE = 51, PROTOCOL = 52,
}

test("linux.socket.ip carries the IP_ options and nothing else", function()
	check.carries("socket.ip", sk.ip, options)
	for key in pairs(sk.ip) do
		assert(options[key] ~= nil, ("linux.socket.ip.%s is not an option"):format(key))
	end
end)

