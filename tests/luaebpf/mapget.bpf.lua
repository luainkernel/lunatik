-- see mapget.sh
local corpus = require("tests.luaebpf.corpus")
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")

local pack, insert, concat = string.pack, table.insert, table.concat

local PRESENT <const> = 7
local ABSENT  <const> = 11
local INDEX   <const> = 1
local BEYOND  <const> = 9   -- past the array's entries, where a lookup answers NULL
local SEEDED  <const> = 42
local COUNT   <const> = 55
local BASE    <const> = 100 -- so an array value of zero is still a number the case can tell
local MISS    <const> = 9
local ENTRIES <const> = 64
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local KEY   <const> = "I4"
local VALUE <const> = "I4"
local BIG   <const> = "I8"

local flows = map.hash("flows", {key = KEY, value = VALUE, entries = ENTRIES})
local hits  = map.array("hits", {key = KEY, value = BIG, entries = 4})

local function present(ctx)
	local v = flows[PRESENT]
	if v then
		return v
	end
	return MISS
end

local function absent(ctx)
	local v = flows[ABSENT]
	if v then
		return v
	end
	return MISS
end

-- the key is a byte of the packet, so the lookup takes a value the program computed rather than
-- one the compiler folded into the instruction
local function computed(ctx)
	local p = ctx:packet()
	local k = p:getbyte(0)
	local v = flows[k]
	if v then
		return v
	end
	return MISS
end

-- an array lookup in range answers a pointer even where nothing was written, so the branch a
-- zero value takes is the one Lua takes: 0 is true
local function inrange(ctx)
	local v = hits[INDEX]
	if v then
		return v + BASE
	end
	return MISS
end

local function beyond(ctx)
	local v = hits[BEYOND]
	if v then
		return v + BASE
	end
	return MISS
end

-- more live values than the emitter keeps in registers, so the lookup's own pointer goes to the
-- frame and the verifier has to narrow it there
local function spilled(ctx)
	local a, b, c, d = 1, 2, 3, 4
	local e, f, g, h = 5, 6, 7, 8
	local v = flows[PRESENT]
	local sum = a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8
	if v then
		return v + sum
	end
	return sum
end

xdp.program(present, {name = "present"})
xdp.program(absent, {name = "absent"})
xdp.program(computed, {name = "computed"})
xdp.program(inrange, {name = "inrange"})
xdp.program(beyond, {name = "beyond"})
xdp.program(spilled, {name = "spilled"})

-- what the case seeds each map with, and what each program owes before and after, written from
-- the same constants and the same specs the programs were compiled against
local function bytes(format, value)
	local packed, out = pack(format, value), {}
	for i = 1, #packed do
		insert(out, tostring(packed:byte(i)))
	end
	return concat(out, " ")
end

local SPILLSUM <const> = 1 + 2 * 2 + 3 * 3 + 4 * 4 + 5 * 5 + 6 * 6 + 7 * 7 + 8 * 8

corpus.context("frame", "xdp_md", {ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)

local out = assert(io.open("rows.txt", "w"))
out:write("seed\tflows\t", bytes(KEY, PRESENT), "\t", bytes(VALUE, SEEDED), "\n")
out:write("seed\tflows\t", bytes(KEY, FRAME:byte(1)), "\t", bytes(VALUE, SEEDED), "\n")
out:write("seed\thits\t", bytes(KEY, INDEX), "\t", bytes(BIG, COUNT), "\n")
out:write("expect\tpresent\t", MISS, "\t", SEEDED, "\n")
out:write("expect\tabsent\t", MISS, "\t", MISS, "\n")
out:write("expect\tcomputed\t", MISS, "\t", SEEDED, "\n")
out:write("expect\tinrange\t", BASE, "\t", COUNT + BASE, "\n")
out:write("expect\tbeyond\t", MISS, "\t", MISS, "\n")
out:write("expect\tspilled\t", SPILLSUM, "\t", SEEDED + SPILLSUM, "\n")
out:close()

