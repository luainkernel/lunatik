--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the partition case (see partition.sh).

local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local vmlinux = require("luaebpf.vmlinux")
local tc      = require("bpf.tc")
local map     = require("bpf.map")
local action  = require("linux.tc").action

local pack = string.pack

local KEY     <const> = "I4"
local VALUE   <const> = "I4"
local ENTRIES <const> = 8
local ETHER   <const> = 14 -- the ethernet header the IPv4 one follows
local PROTO   <const> = 23 -- iphdr.protocol, from the frame
local TCP     <const> = 6
local HTTPS   <const> = 443
local PSH     <const> = 0x08
local WORDS   <const> = 4  -- what an IPv4 or TCP header length counts in
local FACTS   <const> = "facts.txt"

-- the ClientHello the walk takes to Lua, and two packets it stops before the call
local stimuli <const> = {"tls", "syn", "icmp"}

local flows = map.hash("flows", {key = KEY, value = VALUE, entries = ENTRIES})
local lua   = tc.runtime("tests/luaebpf/partition")

local function u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

-- the map decides a flow it holds, and only the first packet of one calls Lua, as
-- examples/sniclassify/classify.c does
local function classify(skb)
	local hash = skb:hash()
	local cached = flows[hash]
	if cached then
		skb:priority(cached)
		return action.OK
	end
	local packet = skb:data()
	if packet:getbyte(PROTO) ~= TCP then
		return action.OK
	end
	local tcp = ETHER + (packet:getbyte(ETHER) & 0x0f) * WORDS
	if u16(packet, tcp + 2) ~= HTTPS or packet:getbyte(tcp + 13) & PSH == 0 then
		return action.OK
	end
	local payload = tcp + (packet:getbyte(tcp + 12) >> 4) * WORDS
	local verdict = lua(payload)
	if verdict == nil then
		return action.OK
	end
	flows[hash] = skb:priority()
	return verdict
end

tc.program(classify, {name = "partition"})

for _, name in ipairs(stimuli) do
	corpus.context(name, "__sk_buff", {}, packets[name])
end

-- where the walk lands on the ClientHello, which the callback is handed and sets as the priority
local function payload(frame)
	local tcp = ETHER + (frame:byte(ETHER + 1) & 0x0f) * WORDS
	return tcp + (frame:byte(tcp + 13) >> 4) * WORDS
end

local function offset(struct, name)
	for _, field in ipairs(vmlinux.layout(struct).fields) do
		if field.name == name then
			return field.offset
		end
	end
end

local PRIORITY <const> = payload(packets.tls)

-- prog run builds an skb whose hash reads zero, so both packets of a run take the key 0
local out = assert(io.open(FACTS, "w"))
out:write("key\t", corpus.bytes(pack(KEY, 0)), "\n")
out:write("value\t", corpus.bytes(pack(VALUE, PRIORITY), "%02x"), "\n")
out:write("offset\t", offset("__sk_buff", "priority"), "\n")
out:write("priority\t", PRIORITY, "\n")
out:close()

