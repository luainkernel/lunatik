--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The maps a program file declares: a read, a write and a delete through the kernel's helpers, the
-- test that narrows a lookup, and the value or the struct fields the lookup found.
-- @module luaebpf.emit.map

local insn  = require("luaebpf.insn")
local maps  = require("luaebpf.maps")
local frame = require("luaebpf.emit.frame")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local format   = string.format
local pack     = string.pack
local mathtype = math.type
local abort, aligned, constant, copy = frame.abort, frame.aligned, frame.constant, frame.copy
local extend, fetch, fitsunsigned, getreg = frame.extend, frame.fetch, frame.fitsunsigned, frame.getreg
local isinteger, jumptarget, labelof, reach = frame.isinteger, frame.jumptarget, frame.labelof, frame.reach
local refuse, setreg, tested = frame.refuse, frame.setreg, frame.tested

local BYTE   <const> = frame.BYTE
local INT    <const> = frame.INT
local KEY    <const> = frame.KEY
local MAYBE  <const> = frame.MAYBE
local NBITS  <const> = frame.NBITS
local NIL    <const> = frame.NIL
local RECORD <const> = frame.RECORD
local VALUE  <const> = frame.VALUE

local LOOKUP <const> = 1 -- BPF_FUNC_map_lookup_elem
local UPDATE <const> = 2 -- BPF_FUNC_map_update_elem
local DELETE <const> = 3 -- BPF_FUNC_map_delete_elem
local ANY    <const> = 0 -- BPF_ANY, the flags an unconditional update takes
local ENOENT <const> = -2 -- what a delete of a key the map does not hold answers

local map = {}

-- a map holds what its spec packs, and a compiled function has only numbers to pack
local function mapnumber(f, pc, what)
	refuse(f, pc, "a map %s is a number here", what)
end
map.mapnumber = mapnumber

-- the kernel's bpf.map packs a key and a value with string.pack, which raises on one outside
-- its spec
local function packable(f, pc, spec, what, value)
	if not pcall(pack, spec.format, value) then
		refuse(f, pc, "the map %s %d does not fit '%s'", what, value, spec.format)
	end
end
map.packable = packable

-- a spec narrower than a word holds the values its signedness reaches, and one the program
-- computes outside them takes the default verdict where string.pack would raise
local function fits(f, src, spec)
	if spec.size * BYTE == NBITS then
		return
	end
	if not spec.signed then
		return fitsunsigned(f, src, spec.size)
	end
	local code = f.code
	code:alu(alu.MOV, reg.R5, src)
	extend(f, reg.R5, spec.size)
	code:branch(jump.JNE, reg.R5, src, abort(f))
end

-- the register a key or a value is in, held to its spec: at compile time when the compiler
-- holds it
local function packed(f, pc, state, i, spec, what, scratch)
	local value = state[i]
	if not isinteger(value) then
		mapnumber(f, pc, what)
	end
	local src = getreg(f, pc, state, i, scratch)
	if value.k ~= nil then
		packable(f, pc, spec, what, value.k)
	else
		fits(f, src, spec)
	end
	return src
end
map.packed = packed

-- a helper takes the key and the value by address, so each goes to the slot its frame reserves,
-- zeroed first because one narrower than a word leaves the rest of the slot to what was there
local function mapslot(f, at, src, size)
	f.code:storei(reg.FP, at, 0)
	f.code:store(reg.FP, at, src, size)
end

-- the map in R1 and the key's address in R2, where every map helper wants them. Lua registers
-- live in R6-R9 and the frame, so the call clobbers nothing live.
local function maphelper(f, map)
	local code = f.code
	code:map(reg.R1, map.name)
	code:alu(alu.MOV, reg.R2, reg.FP)
	code:alui(alu.ADD, reg.R2, KEY)
end

local function maplookup(f, ins, state, map, key)
	mapslot(f, KEY, key, map.key.size)
	maphelper(f, map)
	f.code:helper(LOOKUP)
	setreg(f, ins.a, reg.R0)
	state[ins.a] = {t = MAYBE, map = map, name = map.name}
end
map.maplookup = maplookup

local function mapread(f, pc, ins, state, map)
	maplookup(f, ins, state, map, packed(f, pc, state, ins.c, map.key, "key", reg.R3))
end
map.mapread = mapread

-- the value a store writes, held to the map's spec, or nil for the assignment that deletes the entry
local function stored(f, pc, ins, state, map)
	if ins.k then
		local held = constant(f, pc, ins.c)
		if held == nil then
			return nil
		end
		if mathtype(held) ~= "integer" then
			mapnumber(f, pc, "value")
		end
		packable(f, pc, map.value, "value", held)
		f.code:set(reg.R4, held)
		return reg.R4
	end
	local held = state[ins.c]
	if held ~= nil and held.t == NIL then
		return nil
	end
	return packed(f, pc, state, ins.c, map.value, "value", reg.R4)
end

local function mapstore(f, pc, ins, state, map, key)
	local code = f.code
	if map.value.fields ~= nil then
		refuse(f, pc, "a struct map value is read-only in a compiled function")
	end
	local value = stored(f, pc, ins, state, map)
	mapslot(f, KEY, key, map.key.size)
	if value == nil then
		local absent = code:label()
		maphelper(f, map)
		code:helper(DELETE)
		-- the kernel's bpf.map raises on any delete the map refuses but an absent key's (luabpf_map_checkret)
		code:branchi(jump.JEQ, reg.R0, ENOENT, absent)
		code:branchi(jump.JNE, reg.R0, 0, abort(f))
		code:place(absent)
		return
	end
	mapslot(f, VALUE, value, map.value.size)
	maphelper(f, map)
	code:alu(alu.MOV, reg.R3, reg.FP)
	code:alui(alu.ADD, reg.R3, VALUE)
	code:set(reg.R4, ANY)
	code:helper(UPDATE)
	code:branchi(jump.JNE, reg.R0, 0, abort(f)) -- the kernel's bpf.map raises on an update the map refuses
end
map.mapstore = mapstore

-- the map a lookup came from, or the refusal for a register two lookups merged into: a join
-- drops what the paths disagree on, and which map a value is read with is one of those
local function mapfrom(f, pc, value)
	if value.map == nil then
		refuse(f, pc, "a map value here comes from more than one map")
	end
	return value.map
end

-- one field of a struct value, at the offset and the width its codec carries
local function mapfield(f, pc, ins, state, value, key)
	tested(f, pc, value)
	local field = mapfrom(f, pc, value).value.fields[key]
	if field == nil then
		refuse(f, pc, "a map value has no field '%s'", key)
	end
	aligned(f, pc, format("field '%s'", key), field.size)
	f.code:load(reg.R1, fetch(f, ins.b, reg.R1), field.offset, field.size)
	if field.signed and field.size * BYTE < NBITS then
		extend(f, reg.R1, field.size)
	end
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT, name = key}
end
map.mapfield = mapfield

-- the map a write names, or the refusal for a table that is not one
local function mapof(f, pc, state, i)
	local container = state[i]
	if container == nil or not maps.declares(container.k) then
		refuse(f, pc, "a table cannot be written in a compiled function")
	end
	return container.k
end
map.mapof = mapof

-- the value behind a pointer the program has just found non-null, which is the only place the
-- verifier lets it be read. A struct stays the pointer it is, and its fields are read one at a
-- time from there.
local function mapvalue(f, pc, state, i, value)
	local map = mapfrom(f, pc, value)
	local spec = map.value
	if spec.fields ~= nil then
		state[i] = {t = RECORD, map = map, name = value.name}
		return
	end
	f.code:load(reg.R1, fetch(f, i, reg.R1), 0, spec.size)
	if spec.signed and spec.size * BYTE < NBITS then
		extend(f, reg.R1, spec.size)
	end
	setreg(f, i, reg.R1)
	state[i] = {t = INT, name = value.name}
end

-- a lookup is narrowed where the program tests it, and the read goes on the branch that found
-- it good: the verifier refuses it anywhere else, and the other branch carries a nil
local function testlookup(f, pc, ins, state)
	local code, value = f.code, state[ins.a]
	local target = jumptarget(f, pc + 1)
	local truthy = ins.k and target or pc + 2
	local falsy = ins.k and pc + 2 or target
	local null = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), 0, null)
	local taken = copy(state)
	mapvalue(f, pc, taken, ins.a, value)
	code:jump(labelof(f, truthy))
	reach(f, truthy, taken)
	code:place(null)
	code:jump(labelof(f, falsy))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, falsy, state)
	return false
end
map.testlookup = testlookup

return map

