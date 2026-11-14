--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the mapget case (see mapget.sh).

local corpus = require("tests.luaebpf.corpus")
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")

local pack, bytes = string.pack, corpus.bytes

local PRESENT <const> = 7
local ABSENT  <const> = 11
local INDEX   <const> = 1
local BEYOND  <const> = 9   -- past the array's entries, where a lookup answers NULL
local SEEDED  <const> = 42
local COUNT   <const> = 55
local BASE    <const> = 100 -- so an array value of zero is still a number the case can tell
local MISS    <const> = 9
local ENTRIES <const> = 64
local WORD    <const> = 32  -- past the four bytes the key spec packs
local SPAN    <const> = 0x10000 -- past the two bytes the signed key spec packs
local FIRST   <const> = 0xff -- the frame's first byte, so the lookup is on the path the frame takes

local KEY    <const> = "I4"
local VALUE  <const> = "I4"
local BIG    <const> = "I8"
local SIGNED <const> = "i2"

local flows = map.hash("flows", {key = KEY, value = VALUE, entries = ENTRIES})
local hits  = map.array("hits", {key = KEY, value = BIG, entries = 4})
local marks = map.hash("marks", {key = SIGNED, value = VALUE, entries = ENTRIES})
local recent = map.lru_hash("recent", {key = KEY, value = VALUE, entries = ENTRIES})

local function present(keep)
	return function(_)
		local v = flows[PRESENT]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

local function absent(keep)
	return function(_)
		local v = flows[ABSENT]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- the key is a byte of the packet, so the lookup takes a value the program computed rather than
-- one the compiler folded into the instruction
local function computed(keep)
	return function(ctx)
		local p = ctx:packet()
		local k = p:getbyte(0)
		local v = flows[k]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- an array lookup in range answers a pointer even where nothing was written, so the branch a
-- zero value takes is the one Lua takes: 0 is true
local function inrange(keep)
	return function(_)
		local v = hits[INDEX]
		if v then
			keep(v + BASE)
			return
		end
		keep(MISS)
	end
end

local function beyond(keep)
	return function(_)
		local v = hits[BEYOND]
		if v then
			keep(v + BASE)
			return
		end
		keep(MISS)
	end
end

-- more live values than the emitter keeps in registers, so the lookup's own pointer goes to the
-- frame and the verifier has to narrow it there
local function spilled(keep)
	return function(_)
		local a, b, c, d = 1, 2, 3, 4
		local e, f, g, h = 5, 6, 7, 8
		local v = flows[PRESENT]
		local sum = a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8
		if v then
			keep(v + sum)
			return
		end
		keep(sum)
	end
end

-- a key the program computes past what its spec packs, whose low four bytes are the seeded one:
-- string.pack raises on it, so the program owes its default verdict and not the seeded value
local function widekey(keep)
	return function(ctx)
		local p = ctx:packet()
		local k = p:getbyte(0) << WORD | PRESENT
		local v = flows[k]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- a negative key a signed spec packs, and one past its range whose low two bytes are that key
local function negkey(keep)
	return function(ctx)
		local p = ctx:packet()
		local v = marks[-p:getbyte(0)]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

local function narrowkey(keep)
	return function(ctx)
		local p = ctx:packet()
		local v = marks[-p:getbyte(0) - SPAN]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- a register nil on the path that skips the lookup, which the test narrows as it narrows the lookup
local function onepath(keep)
	return function(ctx)
		local p = ctx:packet()
		local v
		if p:getbyte(0) == FIRST then
			v = flows[PRESENT]
		end
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- the same register where the frame skips the lookup, so the test reads the nil itself
local function skipped(keep)
	return function(ctx)
		local p = ctx:packet()
		local v
		if p:getbyte(0) ~= FIRST then
			v = flows[PRESENT]
		end
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

-- an LRU hash, which a lookup reads as it reads a hash
local function lru(keep)
	return function(_)
		local v = recent[PRESENT]
		if v then
			keep(v)
			return
		end
		keep(MISS)
	end
end

local programs = {{"present", present}, {"absent", absent}, {"computed", computed},
	{"inrange", inrange}, {"beyond", beyond}, {"spilled", spilled}, {"widekey", widekey},
	{"negkey", negkey}, {"narrowkey", narrowkey}, {"onepath", onepath}, {"skipped", skipped},
	{"lru", lru}}
for _, program in ipairs(programs) do
	corpus.program(xdp.program, {name = program[1]}, program[2])
end
corpus.close()

-- what a lookup under a key keeps: what it finds where string.pack takes the key, and nothing where
-- it raises, as the kernel's bpf.map does
local function owed(format, key, found)
	return pcall(pack, format, key) and found or "absent"
end

local frame = corpus.frame()

-- what the case seeds each map with, and what each program owes before and after, written from
-- the same constants and the same specs the programs were compiled against, and the byte of the
-- frame the computed keys read
local SPILLSUM <const> = 1 + 2 * 2 + 3 * 3 + 4 * 4 + 5 * 5 + 6 * 6 + 7 * 7 + 8 * 8
local BYTE0    <const> = frame:packet():getbyte(0)
local WIDE     <const> = BYTE0 << WORD | PRESENT
local NEGATIVE <const> = -BYTE0
local NARROW   <const> = NEGATIVE - SPAN

local out = assert(io.open("rows.txt", "w"))
out:write("seed\tflows\t", bytes(pack(KEY, PRESENT)), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("seed\tflows\t", bytes(pack(KEY, BYTE0)), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("seed\thits\t", bytes(pack(KEY, INDEX)), "\t", bytes(pack(BIG, COUNT)), "\n")
out:write("seed\tmarks\t", bytes(pack(SIGNED, NEGATIVE)), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("seed\trecent\t", bytes(pack(KEY, PRESENT)), "\t", bytes(pack(VALUE, SEEDED)), "\n")
out:write("expect\tpresent\t", MISS, "\t", SEEDED, "\n")
out:write("expect\tabsent\t", MISS, "\t", MISS, "\n")
out:write("expect\tcomputed\t", MISS, "\t", SEEDED, "\n")
out:write("expect\tinrange\t", BASE, "\t", COUNT + BASE, "\n")
out:write("expect\tbeyond\t", MISS, "\t", MISS, "\n")
out:write("expect\tspilled\t", SPILLSUM, "\t", SEEDED + SPILLSUM, "\n")
out:write("expect\twidekey\t", owed(KEY, WIDE, MISS), "\t", owed(KEY, WIDE, SEEDED), "\n")
out:write("expect\tnegkey\t", owed(SIGNED, NEGATIVE, MISS), "\t", owed(SIGNED, NEGATIVE, SEEDED), "\n")
out:write("expect\tnarrowkey\t", owed(SIGNED, NARROW, MISS), "\t", owed(SIGNED, NARROW, SEEDED), "\n")
out:write("expect\tonepath\t", MISS, "\t", SEEDED, "\n")
out:write("expect\tskipped\t", MISS, "\t", MISS, "\n")
out:write("expect\tlru\t", MISS, "\t", SEEDED, "\n")
out:close()

