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
local runtime = require("luaebpf.emit.runtime")

local CTX    <const> = context.CTX
local MAYBE  <const> = map.MAYBE
local METHOD <const> = frame.type("method")
local PACKET <const> = packet.PACKET
local RECORD <const> = map.RECORD

local loads = {METHOD = METHOD}

local function moveslot(f, state, a, b)
	local value = state[b]
	if value ~= nil and (value.t & (frame.classes.word | frame.classes.proxy)) ~= 0 then
		frame.setreg(f, a, frame.fetch(f, b, insn.reg.R1))
	end
	state[a] = value
end
loads.moveslot = moveslot

function loads.MOVE(f, _, ins, state)
	moveslot(f, state, ins.a, ins.b)
end

function loads.LOADI(f, pc, ins, state)
	frame.resolve(f, pc, state, ins.a, ins.sbx)
end

function loads.LOADK(f, pc, ins, state)
	frame.resolve(f, pc, state, ins.a, frame.constant(f, pc, ins.bx))
end

function loads.LOADKX(f, pc, ins, state)
	local extra = f.proto.code[pc + 1]
	if extra == nil or extra.op ~= proto.opcodes.EXTRAARG then
		frame.refuse(f, pc, "LOADKX is not followed by EXTRAARG")
	end
	frame.resolve(f, pc, state, ins.a, frame.constant(f, pc, extra.ax))
	frame.reach(f, pc + 2, state)
	return false
end

function loads.LOADFALSE(f, pc, ins, state)
	frame.resolve(f, pc, state, ins.a, false)
end

function loads.LOADTRUE(f, pc, ins, state)
	frame.resolve(f, pc, state, ins.a, true)
end

function loads.LFALSESKIP(f, pc, ins, state)
	frame.resolve(f, pc, state, ins.a, false)
	f.code:jump(frame.labelof(f, pc + 2))
	frame.reach(f, pc + 2, state)
	return false
end

function loads.LOADNIL(f, pc, ins, state)
	for i = ins.a, ins.a + ins.b do
		frame.resolve(f, pc, state, i, nil)
	end
end

local function upvalue(f, pc, i)
	local name, value = debug.getupvalue(f.fn, i + 1)
	if name == nil then
		frame.refuse(f, pc, "upvalue #%d does not exist", i + 1)
	end
	return value, name
end

function loads.GETUPVAL(f, pc, ins, state)
	local value, name = upvalue(f, pc, ins.b)
	frame.resolve(f, pc, state, ins.a, value, name)
end

-- a struct map value, or the lookup that finds one before the program has tested it
local function isrecord(value)
	return value ~= nil and (value.t == RECORD
		or value.t == MAYBE and value.map ~= nil and value.map.value.fields ~= nil)
end

-- bpf.map decodes a struct value into a table keyed by the layout's names, which has no index
local function indexable(f, pc, container)
	if isrecord(container) then
		frame.refuse(f, pc, "a struct map value is read by field name, not by index")
	end
end

local function lookup(f, pc, container, key, name)
	if container == nil or type(container.k) ~= "table" then
		frame.refuse(f, pc, "'%s' is read from a value the compiler cannot resolve", name)
	end
	return container.k[key]
end

-- a field of any upvalue table is this opcode too, not only a global, which is _ENV's field
function loads.GETTABUP(f, pc, ins, state)
	local env, upname = upvalue(f, pc, ins.b)
	local key = tostring(frame.constant(f, pc, ins.c))
	if maps.declares(env) then
		map.mapnumber(f, pc, "key")
	end
	local value = lookup(f, pc, {k = env}, key, upname)
	if value == nil then
		local read = upname == "_ENV" and string.format("global '%s'", key) or string.format("'%s.%s'", upname, key)
		frame.refuse(f, pc, "%s is not a compile-time value", read)
	end
	frame.resolve(f, pc, state, ins.a, value, key)
end

function loads.GETFIELD(f, pc, ins, state)
	local key = tostring(frame.constant(f, pc, ins.c))
	local container = state[ins.b]
	if container ~= nil and container.t == CTX then
		return context.contextfield(f, pc, key)
	end
	if isrecord(container) then
		return map.mapfield(f, pc, ins, state, container, key)
	end
	if container ~= nil and container.t == packet.VIEW then
		return packet.viewfield(f, pc, ins, state, container, key)
	end
	if container ~= nil and maps.declares(container.k) then
		map.mapnumber(f, pc, "key")
	end
	local name = container ~= nil and container.name or "a table"
	frame.resolve(f, pc, state, ins.a, lookup(f, pc, container, key, name), key)
end

function loads.SETFIELD(f, pc, ins, state)
	local container = state[ins.a]
	if container ~= nil and container.t == CTX then
		return context.contextfield(f, pc, tostring(frame.constant(f, pc, ins.b)))
	end
	if isrecord(container) then
		frame.refuse(f, pc, "a struct map value is read-only in a compiled function")
	end
	map.mapof(f, pc, state, ins.a)
	map.mapnumber(f, pc, "key")
end

-- a global is a field of the _ENV upvalue, and so is any other upvalue table's
function loads.SETTABUP(f, pc, ins, _)
	local env, upname = upvalue(f, pc, ins.a)
	if maps.declares(env) then
		map.mapnumber(f, pc, "key")
	end
	frame.refuse(f, pc, upname == "_ENV" and "a global cannot be assigned in a compiled function"
		or "a table cannot be written in a compiled function")
end

function loads.SETTABLE(f, pc, ins, state)
	local target = map.mapof(f, pc, state, ins.a)
	map.mapstore(f, pc, ins, state, target, map.packed(f, pc, state, ins.b, target.key, "key", insn.reg.R3))
end

function loads.SETI(f, pc, ins, state)
	local target = map.mapof(f, pc, state, ins.a)
	map.packable(f, pc, target.key, "key", ins.b)
	f.code:set(insn.reg.R3, ins.b)
	map.mapstore(f, pc, ins, state, target, insn.reg.R3)
end

function loads.GETI(f, pc, ins, state)
	local container = state[ins.b]
	indexable(f, pc, container)
	if container ~= nil and maps.declares(container.k) then
		map.packable(f, pc, container.k.key, "key", ins.c)
		f.code:set(insn.reg.R3, ins.c)
		return map.maplookup(f, ins, state, container.k, insn.reg.R3)
	end
	local name = container ~= nil and container.name or "a table"
	frame.resolve(f, pc, state, ins.a, lookup(f, pc, container, ins.c, name))
end

function loads.GETTABLE(f, pc, ins, state)
	local key = state[ins.c]
	local container = state[ins.b]
	indexable(f, pc, container)
	if container ~= nil and maps.declares(container.k) then
		return map.mapread(f, pc, ins, state, container.k)
	end
	local name = container ~= nil and container.name or "a table"
	if key == nil or key.k == nil then
		frame.refuse(f, pc, "'%s' is indexed by a value the compiler cannot resolve", name)
	end
	frame.resolve(f, pc, state, ins.a, lookup(f, pc, container, key.k, name))
end

-- what a compiled method is called on: a proxy, or a struct codec of the body, whose view the call makes
local function receiver(value)
	return value ~= nil and ((value.t & frame.classes.proxy) ~= 0 or packet.iscodec(value))
end

-- the receiver goes to A+1 and the method to A, which the call then reads back
function loads.SELF(f, pc, ins, state)
	local recv = state[ins.b]
	if recv ~= nil and runtime.isproxy(recv.k) then
		return runtime.self(f, pc, ins, state)
	end
	if not receiver(recv) then
		frame.refuse(f, pc, "a method call cannot be compiled")
	end
	moveslot(f, state, ins.a + 1, ins.b)
	state[ins.a] = {t = METHOD, name = tostring(frame.constant(f, pc, ins.c)), recv = recv}
end

function loads.LEN(f, pc, ins, state)
	local value = state[ins.b]
	if value ~= nil and value.t == CTX then
		return context.contextlen(f, pc, ins, state)
	end
	if value == nil or value.t ~= PACKET then
		frame.refuse(f, pc, "'#' cannot be applied in a compiled function")
	end
	packet.packetlen(f, pc, ins, state)
end

return loads

