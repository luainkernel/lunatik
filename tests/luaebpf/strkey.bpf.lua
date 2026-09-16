-- see strkey.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp")
local map     = require("bpf.map")
local xdp     = require("bpf.xdp")

local pack, insert, concat = string.pack, table.insert, table.concat

local WIDE    <const> = "c64" -- what the kernel script opens the same map with
local NARROW  <const> = "c16"
local VALUE   <const> = "I4"
local ENTRIES <const> = 16
local SNI     <const> = 115 -- the host name in the whole ClientHello
local NAME    <const> = 11  -- and its length
local ETHER   <const> = 14  -- bytes the map was never keyed with
local NAMELEN <const> = 114 -- where the name's length sits, so the bound is the program's own
local SHORT   <const> = 16  -- the narrow map's own key width
local MISS    <const> = 9   -- a verdict no seeded value takes
local KEPT    <const> = 6   -- what the compiled program writes under the key it built
local IFINDEX <const> = 1
local QUEUE   <const> = 0

local flows  = map.hash("flows", {key = WIDE, value = VALUE, entries = ENTRIES})
local shorts = map.hash("shorts", {key = NARROW, value = VALUE, entries = ENTRIES})
local seen   = map.hash("seen", {key = WIDE, value = VALUE, entries = ENTRIES})

-- the key the kernel script wrote through lib/bpf/map.lua with the same spec
local function found(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	local v = flows[s]
	if v then
		return v
	end
	return MISS
end

-- bytes the map was never keyed with
local function missing(ctx)
	local p = ctx:packet()
	local s = p:getstring(ETHER, NAME)
	local v = flows[s]
	if v then
		return v
	end
	return MISS
end

-- the key spec is the map's, not the buffer's: the helper reads sixteen bytes of a buffer of
-- sixty-four, which is what the script packed with "c16"
local function narrow(ctx)
	local p = ctx:packet()
	local n = p:getbyte(NAMELEN)
	if n > SHORT then
		return action.ABORTED
	end
	local s = p:getstring(SNI, n)
	local v = shorts[s]
	if v then
		return v
	end
	return MISS
end

local function record(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	seen[s] = KEPT
	return action.PASS
end

-- a default no row returns, so a lookup after a read that failed is the verdict the file asked
-- for rather than a number the failure path left behind
xdp.program(found, {name = "found", default = action.REDIRECT})
xdp.program(missing, {name = "missing", default = action.REDIRECT})
xdp.program(narrow, {name = "narrow", default = action.REDIRECT})
xdp.program(record, {name = "record", default = action.REDIRECT})

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end

-- what the case hands bpftool and what it reads back, from the same constants and the same specs
-- the programs were compiled against: a key goes on the command line as decimal bytes, and a
-- value comes back as the hex pairs bpftool prints
local function rendered(format, value, how)
	local packed, out = pack(format, value), {}
	for i = 1, #packed do
		insert(out, how:format(packed:byte(i)))
	end
	return concat(out, " ")
end

local out = assert(io.open("rows.txt", "w"))
out:write("key\tseen\t", rendered(WIDE, packets.tls:sub(SNI + 1, SNI + NAME), "%d"), "\n")
out:write("value\tkept\t", rendered(VALUE, KEPT, "%02x"), "\n")
out:write("expect\tfound\t", action.DROP, "\n")
out:write("expect\tmissing\t", MISS, "\n")
out:write("expect\tnarrow\t", action.TX, "\n")
out:write("expect\trecord\t", action.PASS, "\n")
out:write("truncated\tfound\t", action.REDIRECT, "\n")
out:close()

