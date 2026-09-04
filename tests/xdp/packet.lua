--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Packet predicates for the xdp test callbacks: the namespace emits IPv6 autoconf traffic of
-- its own, so a callback acts only on the ping.

local ETH_HI   <const> = 12 -- ethertype, then IPv4 protocol, then ICMP type
local ETH_LO   <const> = 13
local IPPROTO  <const> = 23
local ICMPTYPE <const> = 34
local ICMP     <const> = 1
local ECHO     <const> = 8

local packet = {}

function packet.isping(data)
	return data:getuint8(ETH_HI) == 0x08 and data:getuint8(ETH_LO) == 0x00 and data:getuint8(IPPROTO) == ICMP and
		data:getuint8(ICMPTYPE) == ECHO
end

return packet

