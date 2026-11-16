--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Packet predicates for the tc test callbacks: the namespace emits IPv6 autoconf traffic of
-- its own, so a callback acts only on the ping, whose echo reply the classifier's egress carries.

local eth     = require("linux.eth").proto
local ipproto = require("linux.socket").ipproto

local ETH_HI    <const> = 12 -- ethertype, then IPv4 protocol, then ICMP type
local ETH_LO    <const> = 13
local IPPROTO   <const> = 23
local ICMPTYPE  <const> = 34
local ICMP      <const> = ipproto.ICMP
local ECHOREPLY <const> = 0
local ECHO      <const> = 8

local packet = {}

function packet.isping(data)
	return data:getuint8(ETH_HI) << 8 | data:getuint8(ETH_LO) == eth.IP and data:getuint8(IPPROTO) == ICMP and
		data:getuint8(ICMPTYPE) == ECHOREPLY
end

-- spelled whole as isping is: the programs luaebpf compiles take this module, and a tail call does not compile
function packet.isecho(data)
	return data:getuint8(ETH_HI) << 8 | data:getuint8(ETH_LO) == eth.IP and data:getuint8(IPPROTO) == ICMP and
		data:getuint8(ICMPTYPE) == ECHO
end

return packet

