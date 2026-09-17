--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The XDP program of the SNI filter; examples/filter/sni.lua writes its blocklist.

local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")
local sni    = require("examples.common.sni")

local ETHER   <const> = 14    -- the ethernet header the IPv4 one follows
local PROTO   <const> = 23    -- iphdr.protocol, from the frame
local TCP     <const> = 6
local HTTPS   <const> = 443
local PSH     <const> = 0x08
local WORDS   <const> = 4     -- what an IPv4 or TCP header length counts in
local KEY     <const> = "c64" -- the widest host name a compiled read answers
local VALUE   <const> = "I8"
local ENTRIES <const> = 1024

-- the policy and the evidence in one map: examples/filter/sni.lua writes a zero under every name
-- it blocks, and the program counts what it dropped under the key it read out of the packet
local blocked = map.hash("blocked", {key = KEY, value = VALUE, entries = ENTRIES})

local function filter(ctx)
	local packet = ctx:packet()
	if packet:getbyte(PROTO) ~= TCP then
		return action.PASS
	end
	local tcp = ETHER + (packet:getbyte(ETHER) & 0x0f) * WORDS
	if sni.u16(packet, tcp + 2) ~= HTTPS or packet:getbyte(tcp + 13) & PSH == 0 then
		return action.PASS
	end

	local payload = tcp + (packet:getbyte(tcp + 12) >> 4) * WORDS
	local host = sni.host(packet, payload)
	if host == nil then
		return action.PASS
	end
	local hits = blocked[host]
	if hits then
		blocked[host] = hits + 1
		return action.DROP
	end
	return action.PASS
end

return xdp.program(filter, {name = "filter_sni"})

