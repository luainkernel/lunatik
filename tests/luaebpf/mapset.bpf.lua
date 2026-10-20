--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the mapset case (see mapset.sh).

local corpus = require("tests.luaebpf.corpus")
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local pack, bytes = string.pack, corpus.bytes

local WRITTEN <const> = 7
local DELETED <const> = 3
local SPARE   <const> = 21 -- never written, so deleting it is the no-op Lua makes of it
local KEPT    <const> = 4  -- seeded, and named only by keys past the spec, so it stays
local WIDE    <const> = 22 -- named only by values and keys past the spec, so it stays absent
local INDEX   <const> = 2
local STORED  <const> = 42
local SEEDED  <const> = 5
local COUNT   <const> = 55
local DONE    <const> = 1
local WORD    <const> = 32      -- past the four bytes the key and the value specs pack
local SPAN    <const> = 0x10000 -- past the two bytes the signed value spec packs

local KEY    <const> = "I4"
local VALUE  <const> = "I4"
local BIG    <const> = "I8"
local SIGNED <const> = "i2"

-- bpftool takes a key as decimal bytes and prints a value as hex ones
local HEX <const> = "%02x"

local flows  = map.hash("flows", {key = KEY, value = VALUE, entries = 64})
local hits   = map.array("hits", {key = KEY, value = BIG, entries = 4})
local levels = map.hash("levels", {key = KEY, value = SIGNED, entries = 4})
local one    = map.hash("one", {key = KEY, value = VALUE, entries = 1})

local function update(_)
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

local function remove(_)
	flows[DELETED] = nil
	return DONE
end

local function missing(_)
	flows[SPARE] = nil
	return DONE
end

local function counter(_)
	hits[INDEX] = COUNT
	return DONE
end

-- a value the program computes past what its spec packs, whose low four bytes are STORED
local function widevalue(ctx)
	local p = ctx:packet()
	flows[WIDE] = p:getbyte(0) << WORD | STORED
	return DONE
end

-- a key past the spec whose low four bytes are WIDE, written and deleted
local function widekey(ctx)
	local p = ctx:packet()
	flows[p:getbyte(0) << WORD | WIDE] = STORED
	return DONE
end

local function widedelete(ctx)
	local p = ctx:packet()
	flows[p:getbyte(0) << WORD | KEPT] = nil
	return DONE
end

-- a negative value a signed spec packs, and one past its range whose low two bytes are the same
local function negvalue(ctx)
	local p = ctx:packet()
	levels[1] = -p:getbyte(0)
	return DONE
end

local function narrowvalue(ctx)
	local p = ctx:packet()
	levels[2] = -p:getbyte(0) - SPAN
	return DONE
end

-- writes the map refuses, which the kernel's bpf.map raises on: an index past the array's
-- entries, a second key in a hash of one entry, and a delete from an array
local function overflow(ctx)
	local p = ctx:packet()
	hits[p:getbyte(0)] = COUNT
	return DONE
end

local function full(_)
	one[WRITTEN] = STORED
	one[DELETED] = STORED
	return DONE
end

local function arraydelete(_)
	hits[INDEX] = nil
	return DONE
end

local programs = {{"update", update}, {"computed", computed}, {"remove", remove},
	{"missing", missing}, {"counter", counter}, {"widevalue", widevalue}, {"widekey", widekey},
	{"widedelete", widedelete}, {"negvalue", negvalue}, {"narrowvalue", narrowvalue},
	{"overflow", overflow}, {"full", full}, {"arraydelete", arraydelete}}
for _, program in ipairs(programs) do
	xdp.program(program[2], {name = program[1]})
end

local frame = corpus.frame()

local function key(value)
	return bytes(pack(KEY, value))
end

-- the verdict a store owes: DONE where string.pack takes what it packs, and the default where
-- it raises, as the kernel's bpf.map does
local function owed(format, value)
	return pcall(pack, format, value) and DONE or action.PASS
end

local BYTE0    <const> = frame:packet():getbyte(0)
local NEGATIVE <const> = -BYTE0

local out = assert(io.open("rows.txt", "w"))
out:write("seed\tflows\t", key(DELETED), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("seed\tflows\t", key(KEPT), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("run\tupdate\t", DONE, "\n")
out:write("run\tcomputed\t", DONE, "\n")
out:write("run\tremove\t", DONE, "\n")
out:write("run\tmissing\t", DONE, "\n")
out:write("run\tcounter\t", DONE, "\n")
out:write("run\twidevalue\t", owed(VALUE, BYTE0 << WORD | STORED), "\n")
out:write("run\twidekey\t", owed(KEY, BYTE0 << WORD | WIDE), "\n")
out:write("run\twidedelete\t", owed(KEY, BYTE0 << WORD | KEPT), "\n")
out:write("run\tnegvalue\t", owed(SIGNED, NEGATIVE), "\n")
out:write("run\tnarrowvalue\t", owed(SIGNED, NEGATIVE - SPAN), "\n")
out:write("run\toverflow\t", action.PASS, "\n")
out:write("run\tfull\t", action.PASS, "\n")
out:write("run\tarraydelete\t", action.PASS, "\n")
out:write("check\tflows\t", key(WRITTEN), "\t", bytes(pack(VALUE, STORED), HEX), "\n")
out:write("check\tflows\t", key(BYTE0), "\t", bytes(pack(VALUE, STORED), HEX), "\n")
out:write("check\tflows\t", key(DELETED), "\tabsent\n")
out:write("check\tflows\t", key(SPARE), "\tabsent\n")
out:write("check\tflows\t", key(WIDE), "\tabsent\n")
out:write("check\tflows\t", key(KEPT), "\t", bytes(pack(VALUE, SEEDED), HEX), "\n")
out:write("check\thits\t", key(INDEX), "\t", bytes(pack(BIG, COUNT), HEX), "\n")
out:write("check\tlevels\t", key(1), "\t", bytes(pack(SIGNED, NEGATIVE), HEX), "\n")
out:write("check\tlevels\t", key(2), "\tabsent\n")
out:write("check\tone\t", key(WRITTEN), "\t", bytes(pack(VALUE, STORED), HEX), "\n")
out:write("check\tone\t", key(DELETED), "\tabsent\n")
out:close()

