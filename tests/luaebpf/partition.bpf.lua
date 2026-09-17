-- see partition.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local vmlinux = require("luaebpf.vmlinux")
local tc      = require("bpf.tc")
local map     = require("bpf.map")
local action  = require("linux.tc")

local pack, insert, concat = string.pack, table.insert, table.concat

local KEY     <const> = "I4"
local VALUE   <const> = "I4"
local ENTRIES <const> = 8
local ETHER   <const> = 14 -- the ethernet header the IPv4 one follows
local TCP     <const> = 6
local HTTPS   <const> = 443
local PSH     <const> = 0x08
local PROTO   <const> = 23 -- iphdr.protocol, from the frame
local WORDS   <const> = 4  -- what an IPv4 or TCP header length counts in
-- prog run builds the skb on loopback; convert___skb_to_skb leaves the hash it is given at zero,
-- so both packets of one run take the same key and the second is the cached one
local IFINDEX <const> = 1

-- the ClientHello the walk accepts, and the two packets it rejects at each of its tests
local stimuli <const> = {"tls", "syn", "icmp"}

local flows = map.hash("flows", {key = KEY, value = VALUE, entries = ENTRIES})
local lua   = tc.runtime()

local function u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

-- the shape examples/sniclassify/sni.bpf.lua deploys: the map decides a flow already seen, and
-- only the first packet of one pays for the call into Lua
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
	if u16(packet, tcp + 2) ~= HTTPS or packet:getbyte(tcp + 13) & PSH == 0 then
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

tc.program(classify, {name = "partition"})

for _, name in ipairs(stimuli) do
	corpus.context(name, "__sk_buff", {ifindex = IFINDEX, hash = 0}, packets[name])
end

-- bpftool takes a key as decimal bytes and prints a value as hex ones, both from the same spec
-- the map was declared with
local function bytes(format, value, how)
	local packed, out = pack(format, value), {}
	for i = 1, #packed do
		insert(out, how:format(packed:byte(i)))
	end
	return concat(out, " ")
end

-- where the program's walk lands on the ClientHello, off the same bytes it reads, which is the
-- argument the callback is handed and so the priority it sets
local function payload(frame)
	local tcp = ETHER + (frame:byte(ETHER + 1) & 0x0f) * WORDS
	return tcp + (frame:byte(tcp + 13) >> 4) * WORDS
end

local function field(name)
	for _, member in ipairs(vmlinux.layout("__sk_buff").fields) do
		if member.name == name then
			return member.offset
		end
	end
end

local PRIORITY <const> = payload(packets.tls)

local out = assert(io.open("facts.txt", "w"))
out:write("key\t", bytes(KEY, 0, "%d"), "\n")
out:write("value\t", bytes(VALUE, PRIORITY, "%02x"), "\n")
out:write("offset\t", field("priority"), "\n")
out:write("priority\t", PRIORITY, "\n")
out:close()

