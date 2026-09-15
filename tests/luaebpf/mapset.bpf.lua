-- see mapset.sh
local corpus = require("tests.luaebpf.corpus")
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")

local pack, insert, concat = string.pack, table.insert, table.concat

local WRITTEN <const> = 7
local DELETED <const> = 3
local SPARE   <const> = 21 -- never written, so deleting it is the no-op Lua makes of it
local INDEX   <const> = 2
local STORED  <const> = 42
local SEEDED  <const> = 5
local COUNT   <const> = 55
local DONE    <const> = 1
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local KEY   <const> = "I4"
local VALUE <const> = "I4"
local BIG   <const> = "I8"

local flows = map.hash("flows", {key = KEY, value = VALUE, entries = 64})
local hits  = map.array("hits", {key = KEY, value = BIG, entries = 4})

local function update(ctx)
	flows[WRITTEN] = STORED
	return DONE
end

-- the key is a byte of the packet, so the store takes one the program computed rather than one
-- the compiler folded into the instruction
local function computed(ctx)
	local p = ctx:packet()
	local k = p:getbyte(0)
	flows[k] = STORED
	return DONE
end

local function remove(ctx)
	flows[DELETED] = nil
	return DONE
end

local function missing(ctx)
	flows[SPARE] = nil
	return DONE
end

local function counter(ctx)
	hits[INDEX] = COUNT
	return DONE
end

xdp.program(update, {name = "update"})
xdp.program(computed, {name = "computed"})
xdp.program(remove, {name = "remove"})
xdp.program(missing, {name = "missing"})
xdp.program(counter, {name = "counter"})

corpus.context("frame", "xdp_md", {ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)

-- bpftool takes a key as decimal bytes and prints a value as hex ones, both from the same spec
-- the map was declared with
local function bytes(format, value, how)
	local packed, out = pack(format, value), {}
	for i = 1, #packed do
		insert(out, how:format(packed:byte(i)))
	end
	return concat(out, " ")
end

local function key(value)
	return bytes(KEY, value, "%d")
end

local out = assert(io.open("rows.txt", "w"))
out:write("seed\tflows\t", key(DELETED), "\t", bytes(VALUE, SEEDED, "%d"), "\n")
out:write("run\tupdate\nrun\tcomputed\nrun\tremove\nrun\tmissing\nrun\tcounter\n")
out:write("check\tflows\t", key(WRITTEN), "\t", bytes(VALUE, STORED, "%02x"), "\n")
out:write("check\tflows\t", key(FRAME:byte(1)), "\t", bytes(VALUE, STORED, "%02x"), "\n")
out:write("check\tflows\t", key(DELETED), "\tabsent\n")
out:write("check\tflows\t", key(SPARE), "\tabsent\n")
out:write("check\thits\t", key(INDEX), "\t", bytes(BIG, COUNT, "%02x"), "\n")
out:close()

