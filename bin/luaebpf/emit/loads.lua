--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- MOVE, the LOAD opcodes, GETUPVAL, the table and field opcodes, SELF and LEN: a value the file body
-- computed becomes a constant of the program, and a table the body declared as a map is read and
-- written through the map's helpers.
-- @module luaebpf.emit.loads

local insn    = require("luaebpf.insn")
local maps    = require("luaebpf.maps")
local proto   = require("luaebpf.proto")
local frame   = require("luaebpf.emit.frame")
local context = require("luaebpf.emit.context")
local packet  = require("luaebpf.emit.packet")
local map     = require("luaebpf.emit.map")

local reg        = insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local getupvalue = debug.getupvalue
local constant, fetch, labelof, reach = frame.constant, frame.fetch, frame.labelof, frame.reach
local refuse, resolve, setreg = frame.refuse, frame.resolve, frame.setreg
local classes = frame.classes
local contextfield, contextlen = context.contextfield, context.contextlen
local packetlen = packet.packetlen
local mapfield, maplookup, mapnumber, mapof = map.mapfield, map.maplookup, map.mapnumber, map.mapof
local mapread, mapstore, packable, packed = map.mapread, map.mapstore, map.packable, map.packed

local CTX    <const> = context.CTX
local MAYBE  <const> = map.MAYBE
local METHOD <const> = frame.type("method")
local PACKET <const> = packet.PACKET
local RECORD <const> = map.RECORD

local loads = {METHOD = METHOD}

local function moveslot(f, state, a, b)
	local value = state[b]
	if value ~= nil and (value.t & (classes.word | classes.proxy)) ~= 0 then
		setreg(f, a, fetch(f, b, reg.R1))
	end
	state[a] = value
end
loads.moveslot = moveslot

function loads.MOVE(f, _, ins, state)
	moveslot(f, state, ins.a, ins.b)
end

function loads.LOADI(f, pc, ins, state)
	resolve(f, pc, state, ins.a, ins.sbx)
end

function loads.LOADK(f, pc, ins, state)
	resolve(f, pc, state, ins.a, constant(f, pc, ins.bx))
end

function loads.LOADKX(f, pc, ins, state)
	local extra = f.proto.code[pc + 1]
	if extra == nil or extra.op ~= opcodes.EXTRAARG then
		refuse(f, pc, "LOADKX is not followed by EXTRAARG")
	end
	resolve(f, pc, state, ins.a, constant(f, pc, extra.ax))
	reach(f, pc + 2, state)
	return false
end

function loads.LOADFALSE(f, pc, ins, state)
	resolve(f, pc, state, ins.a, false)
end

function loads.LOADTRUE(f, pc, ins, state)
	resolve(f, pc, state, ins.a, true)
end

function loads.LFALSESKIP(f, pc, ins, state)
	resolve(f, pc, state, ins.a, false)
	f.code:jump(labelof(f, pc + 2))
	reach(f, pc + 2, state)
	return false
end

function loads.LOADNIL(f, pc, ins, state)
	for i = ins.a, ins.a + ins.b do
		resolve(f, pc, state, i, nil)
	end
end

local function upvalue(f, pc, i)
	local name, value = getupvalue(f.fn, i + 1)
	if name == nil then
		refuse(f, pc, "upvalue #%d does not exist", i + 1)
	end
	return value, name
end

function loads.GETUPVAL(f, pc, ins, state)
	local value, name = upvalue(f, pc, ins.b)
	resolve(f, pc, state, ins.a, value, name)
end

-- a struct map value, or the lookup that finds one before the program has tested it
local function isrecord(value)
	return value ~= nil and (value.t == RECORD
		or value.t == MAYBE and value.map ~= nil and value.map.value.fields ~= nil)
end

-- bpf.map decodes a struct value into a table keyed by the layout's names, which has no index
local function indexable(f, pc, container)
	if isrecord(container) then
		refuse(f, pc, "a struct map value is read by field name, not by index")
	end
end

local function lookup(f, pc, container, key, name)
	if container == nil or type(container.k) ~= "table" then
		refuse(f, pc, "'%s' is read from a value the compiler cannot resolve", name)
	end
	return container.k[key]
end

-- a field of any upvalue table is this opcode too, not only a global, which is _ENV's field
function loads.GETTABUP(f, pc, ins, state)
	local env, upname = upvalue(f, pc, ins.b)
	local key = tostring(constant(f, pc, ins.c))
	if maps.declares(env) then
		mapnumber(f, pc, "key")
	end
	local value = lookup(f, pc, {k = env}, key, upname)
	if value == nil then
		local read = upname == "_ENV" and format("global '%s'", key) or format("'%s.%s'", upname, key)
		refuse(f, pc, "%s is not a compile-time value", read)
	end
	resolve(f, pc, state, ins.a, value, key)
end

function loads.GETFIELD(f, pc, ins, state)
	local key = tostring(constant(f, pc, ins.c))
	local container = state[ins.b]
	if container ~= nil and container.t == CTX then
		return contextfield(f, pc, key)
	end
	if isrecord(container) then
		return mapfield(f, pc, ins, state, container, key)
	end
	if container ~= nil and maps.declares(container.k) then
		mapnumber(f, pc, "key")
	end
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key, name), key)
end

function loads.SETFIELD(f, pc, ins, state)
	local container = state[ins.a]
	if container ~= nil and container.t == CTX then
		return contextfield(f, pc, tostring(constant(f, pc, ins.b)))
	end
	if isrecord(container) then
		refuse(f, pc, "a struct map value is read-only in a compiled function")
	end
	mapof(f, pc, state, ins.a)
	mapnumber(f, pc, "key")
end

-- a global is a field of the _ENV upvalue, and so is any other upvalue table's
function loads.SETTABUP(f, pc, ins, _)
	local env, upname = upvalue(f, pc, ins.a)
	if maps.declares(env) then
		mapnumber(f, pc, "key")
	end
	refuse(f, pc, upname == "_ENV" and "a global cannot be assigned in a compiled function"
		or "a table cannot be written in a compiled function")
end

function loads.SETTABLE(f, pc, ins, state)
	local map = mapof(f, pc, state, ins.a)
	mapstore(f, pc, ins, state, map, packed(f, pc, state, ins.b, map.key, "key", reg.R3))
end

function loads.SETI(f, pc, ins, state)
	local map = mapof(f, pc, state, ins.a)
	packable(f, pc, map.key, "key", ins.b)
	f.code:set(reg.R3, ins.b)
	mapstore(f, pc, ins, state, map, reg.R3)
end

function loads.GETI(f, pc, ins, state)
	local container = state[ins.b]
	indexable(f, pc, container)
	if container ~= nil and maps.declares(container.k) then
		packable(f, pc, container.k.key, "key", ins.c)
		f.code:set(reg.R3, ins.c)
		return maplookup(f, ins, state, container.k, reg.R3)
	end
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, ins.c, name))
end

function loads.GETTABLE(f, pc, ins, state)
	local key = state[ins.c]
	local container = state[ins.b]
	indexable(f, pc, container)
	if container ~= nil and maps.declares(container.k) then
		return mapread(f, pc, ins, state, container.k)
	end
	local name = container ~= nil and container.name or "a table"
	if key == nil or key.k == nil then
		refuse(f, pc, "'%s' is indexed by a value the compiler cannot resolve", name)
	end
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key.k, name))
end

-- the receiver goes to A+1 and the method to A, which the call then reads back
function loads.SELF(f, pc, ins, state)
	local recv = state[ins.b]
	if recv == nil or (recv.t & classes.proxy) == 0 then
		refuse(f, pc, "a method call cannot be compiled")
	end
	moveslot(f, state, ins.a + 1, ins.b)
	state[ins.a] = {t = METHOD, name = tostring(constant(f, pc, ins.c)), recv = recv}
end

function loads.LEN(f, pc, ins, state)
	local value = state[ins.b]
	if value ~= nil and value.t == CTX then
		return contextlen(f, pc, ins, state)
	end
	if value == nil or value.t ~= PACKET then
		refuse(f, pc, "'#' cannot be applied in a compiled function")
	end
	packetlen(f, ins, state)
end

return loads

