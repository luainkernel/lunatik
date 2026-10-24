--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The context proxy: a method reads the field of the context struct its program's constructor maps
-- it to, at the offset the running kernel lays that field out at, and a setter stores there first.
-- @module luaebpf.emit.context

local insn    = require("luaebpf.insn")
local vmlinux = require("luaebpf.vmlinux")
local frame   = require("luaebpf.emit.frame")

local reg = insn.reg
local fetch, fitsunsigned, getreg, isinteger = frame.fetch, frame.fitsunsigned, frame.getreg, frame.isinteger
local refuse, setreg, typename = frame.refuse, frame.setreg, frame.typename

local BYTE <const> = frame.BYTE
local CTX  <const> = frame.type("context", "proxy")
local INT  <const> = frame.INT

local context = {CTX = CTX}

-- the running kernel's own layout of the context struct, read once per program
local function layout(f)
	local unit = f.unit
	if unit.layout == nil then
		unit.layout = {}
		for _, field in ipairs(vmlinux.layout(unit.context.struct).fields) do
			unit.layout[field.name] = field
		end
	end
	return unit.layout
end
context.layout = layout

-- the context is read through its methods, as the kernel's own objects are, so a name read or
-- assigned on it is refused, and a packet bound is named for what it is
local function contextfield(f, pc, key)
	local packet = f.unit.context.packet
	if key == packet.base or key == packet.limit then
		refuse(f, pc, "'%s' is a packet bound, not a number; '#' on the packet is its length", key)
	end
	refuse(f, pc, "the context has no field '%s'", key)
end
context.contextfield = contextfield

-- every field a context proxy exposes is an unsigned word, so the load needs no extension
local function contextload(f, state, a, ctx, field)
	f.code:load(reg.R2, fetch(f, ctx, reg.R1), field.offset, field.size)
	setreg(f, a, reg.R2)
	state[a] = {t = INT, name = field.name}
end

local function contextlen(f, pc, ins, state)
	local length = f.unit.context.length
	if length == nil then
		refuse(f, pc, "the context has no length; '#' on the packet is its length")
	end
	contextload(f, state, ins.a, ins.b, layout(f)[length])
end
context.contextlen = contextlen

-- the value a setter is called with, held to its field as the kernel's own setter holds it: one
-- the compiler holds is refused at its line
local function contextstore(f, pc, ins, state, field)
	local value = state[ins.a + 2]
	if not isinteger(value) then
		refuse(f, pc, "'%s' takes a number, not a %s", field.name, typename(value))
	end
	local src = getreg(f, pc, state, ins.a + 2, reg.R2)
	local bits = field.size * BYTE
	if value.k == nil then
		fitsunsigned(f, src, field.size)
	elseif value.k >> bits ~= 0 then
		refuse(f, pc, "'%s' takes 0 to %d, not %d", field.name, (1 << bits) - 1, value.k)
	end
	f.code:store(fetch(f, ins.a + 1, reg.R1), field.offset, src, field.size)
end

-- a setter is called with the receiver and the value, both of which OP_CALL counts
local VALUEARGS <const> = 2

-- a method reads the field its context maps it to, after storing there the value a setter is
-- called with
local function contextcall(f, pc, ins, state, name)
	local context = f.unit.context
	local member = context.methods[name]
	if not member then
		refuse(f, pc, "the context has no method '%s'", name)
	end
	local field = layout(f)[member]
	if context.writable[name] and ins.b > VALUEARGS then
		contextstore(f, pc, ins, state, field)
	end
	contextload(f, state, ins.a, ins.a + 1, field)
end
context.contextcall = contextcall

return context

