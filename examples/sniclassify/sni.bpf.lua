--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The TC egress program of the SNI classifier; examples/sniclassify/sni.lua is its policy.

local map    = require("bpf.map")
local tc     = require("bpf.tc")
local action = require("linux.tc")
local sni    = require("examples.common.sni")

-- named rather than derived: an example is copied, and a copy compiled from another directory
-- would look its runtime up under that directory's name
local RUNTIME <const> = "examples/sniclassify/sni"
local ETHER   <const> = 14 -- the ethernet header the IPv4 one follows
local PROTO   <const> = 23 -- iphdr.protocol, from the frame
local TCP     <const> = 6
local HTTPS   <const> = 443
local PSH     <const> = 0x08
local WORDS   <const> = 4  -- what an IPv4 or TCP header length counts in
local KEY     <const> = "I4"
local VALUE   <const> = "I4"
local ENTRIES <const> = 65536

-- one entry per flow the policy decided, so only the first packet of one pays for the call
local flows = map.hash("flows", {key = KEY, value = VALUE, entries = ENTRIES})
local lua   = tc.runtime(RUNTIME)

local function classify(skb)
	local cached = flows[skb.hash]
	if cached then
		skb.priority = cached
		return action.ACT_OK
	end

	local packet = skb:packet()
	if packet:getbyte(PROTO) ~= TCP then
		return action.ACT_OK
	end
	local tcp = ETHER + (packet:getbyte(ETHER) & 0x0f) * WORDS
	if sni.u16(packet, tcp + 2) ~= HTTPS or packet:getbyte(tcp + 13) & PSH == 0 then
		return action.ACT_OK
	end

	local payload = tcp + (packet:getbyte(tcp + 12) >> 4) * WORDS
	local verdict = lua(payload)
	if verdict == nil then
		return action.ACT_OK
	end
	flows[skb.hash] = skb.priority
	return verdict
end

return tc.program(classify, {name = "sniclassify", egress = true})

