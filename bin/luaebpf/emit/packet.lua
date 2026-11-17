--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The packet proxy: the reads the kernel's data object publishes, each held to the packet's bounds
-- or copied out of the packet by the call the context names, its length, the view of a struct a codec
-- lays out over it, read a field at a time by the same reads, and the dispatch of a method called on
-- either proxy or on a codec.
-- @module luaebpf.emit.packet

local insn    = require("luaebpf.insn")
local frame   = require("luaebpf.emit.frame")
local context = require("luaebpf.emit.context")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local format = string.format
local abort, aligned, fetch = frame.abort, frame.aligned, frame.fetch
local isinteger, refuse, setreg, typename = frame.isinteger, frame.refuse, frame.setreg, frame.typename
local contextcall, layout = context.contextcall, context.layout

local CTX    <const> = context.CTX
local INT    <const> = frame.INT
local PACKET <const> = frame.type("packet", "proxy")
local VALUE  <const> = frame.VALUE
local VIEW   <const> = frame.type("view", "proxy")

-- MAX_PACKET_OFF: the verifier refuses arithmetic between a packet pointer and a register whose
-- range it does not know, and find_good_pkt_pointers leaves a pointer no range at all once the
-- offset's maximum plus the access would carry it past this. So a read between the bounds tests
-- its offset against the last one its width can start at. Anything above is out of bounds on
-- every XDP frame BPF_PROG_TEST_RUN or a NIC can build, and the interpreter raises there too.
local PACKETMAX <const> = 65535

-- the reads the kernel's own data object publishes (lib/luadata.c), and the load each becomes.
-- There is no getuint64: a Lua integer is 64-bit signed and has no unsigned twin.
local accessors = {
	getbyte   = {size = 1, signed = false},
	getuint8  = {size = 1, signed = false},
	getint8   = {size = 1, signed = true},
	getuint16 = {size = 2, signed = false},
	getint16  = {size = 2, signed = true},
	getuint32 = {size = 4, signed = false},
	getint32  = {size = 4, signed = true},
	getint64  = {size = 8, signed = true},
}

-- an accessor is called with the receiver and the offset, both of which OP_CALL counts
local ACCESSARGS <const> = 2

-- a view is made with the receiver, the packet and the offset, each of which OP_CALL counts
local VIEWARGS <const> = 3

local packet = {PACKET = PACKET, VIEW = VIEW}

-- data and data_end, which the kernel rewrites a four-byte context load of into a full pointer
local function bounds(f)
	local packet, fields = f.unit.context.packet, layout(f)
	return fields[packet.base], fields[packet.limit]
end

-- dst := the offset in Lua register at, plus a constant
local function offset(f, at, plus, dst)
	frame.move(f, fetch(f, at, dst), dst)
	if plus ~= 0 then
		f.code:alui(alu.ADD, dst, plus)
	end
end

-- One access, self-contained: data and data_end are re-read from the context rather than kept
-- live, so the proxy is one register that survives a call and cannot go stale.
local function directread(f, pc, source, at, plus, access, what)
	local code, base, limit = f.code, bounds(f)
	aligned(f, pc, what, access.size)
	offset(f, at, plus, reg.R4)
	local ptr = fetch(f, source, reg.R3)
	code:load(reg.R1, ptr, base.offset, base.size)
	code:load(reg.R2, ptr, limit.offset, limit.size)
	code:branchi(jump.JGT, reg.R4, PACKETMAX - access.size, abort(f))
	code:alu(alu.ADD, reg.R1, reg.R4)
	if f.drop ~= "bounds" then
		code:alu(alu.MOV, reg.R4, reg.R1)
		code:alui(alu.ADD, reg.R4, access.size)
		code:branch(jump.JGT, reg.R4, reg.R2, abort(f))
	end
	code:load(reg.R1, reg.R1, 0, access.size)
end

-- loadbytes, bpf_skb_load_bytes on TC, copies the bytes into the frame's value slot wherever the skb
-- holds them, and answers non-zero past the packet, where the interpreter raises. It takes the low
-- 32 bits of the offset, so the offset is tested against copymax first: one above it whose low 32
-- bits fall in the packet would read there.
local function copyread(f, source, at, plus, access, packet)
	local code = f.code
	offset(f, at, plus, reg.R2)
	frame.move(f, frame.fetch(f, source, reg.R1), reg.R1)
	code:branchi(jump.JGT, reg.R2, packet.copymax, frame.abort(f))
	code:alu(alu.MOV, reg.R3, reg.FP)
	code:alui(alu.ADD, reg.R3, VALUE)
	code:set(reg.R4, access.size)
	code:helper(packet.loadbytes)
	if f.drop ~= "loadbytes" then
		code:branchi(jump.JNE, reg.R0, 0, frame.abort(f))
	end
	code:load(reg.R1, reg.FP, VALUE, access.size)
end

-- R1 := the access's bytes at the offset in Lua register at plus a constant, of the packet in Lua
-- register source, unextended
local function packetload(f, pc, source, at, plus, access, what)
	local packet = f.unit.context.packet
	if packet.loadbytes ~= nil then
		copyread(f, source, at, plus, access, packet)
	else
		directread(f, pc, source, at, plus, access, what)
	end
end

local function packetread(f, pc, ins, state, access, name)
	packetload(f, pc, ins.a + 1, ins.a + 2, 0, access, format("'%s'", name))
	frame.decode(f, state, ins.a, access)
end

local function span(f, ptr)
	local code, base, limit = f.code, bounds(f)
	code:load(reg.R1, ptr, base.offset, base.size)
	code:load(reg.R2, ptr, limit.offset, limit.size)
	code:alu(alu.SUB, reg.R2, reg.R1)
	return reg.R2
end

-- the length is what '#' on the kernel's data object answers and what the interpreted twin reads
-- off the same bytes: the distance between the bounds, or the skb's own where a read copies them
local function packetlen(f, pc, ins, state)
	if f.unit.context.packet.loadbytes ~= nil then
		return context.contextlen(f, pc, ins, state)
	end
	setreg(f, ins.a, span(f, fetch(f, ins.b, reg.R3)))
	state[ins.a] = {t = INT}
end
packet.packetlen = packetlen

-- a method that takes a layer is called with the receiver and the layer, both of which OP_CALL counts
local LAYERARGS <const> = 2

-- the packet proxy is the context register under another type: one register, passed to a
-- subprogram in one argument, with nothing to keep live across a call
local function contextpacket(f, pc, ins, state, name)
	local packet = f.unit.context.packet
	if packet.layered and ins.b > LAYERARGS then
		refuse(f, pc, "'%s' with a layer is not compiled yet", name)
	end
	local ctx = fetch(f, ins.a + 1, reg.R3)
	setreg(f, ins.a, ctx)
	state[ins.a] = {t = PACKET, name = name}
end

local function contextmethod(f, pc, ins, state, callee)
	if callee.name == f.unit.context.packet.method then
		return contextpacket(f, pc, ins, state, callee.name)
	end
	contextcall(f, pc, ins, state, callee.name)
end

-- whether a value the body holds is a struct codec, whose view a compiled function makes
local function iscodec(value)
	local codec = value.k
	return value.t == frame.OTHER and type(codec) == "table" and codec.layout ~= nil and codec.view ~= nil
end
packet.iscodec = iscodec

-- a view of the struct a codec lays out, from an offset into the packet: its register holds the
-- offset, and its state the codec, whose layout a field is read at
local function view(f, pc, ins, state, callee)
	if callee.name ~= "view" then
		refuse(f, pc, "a codec's '%s' cannot be called in a compiled function", callee.name)
	end
	if ins.b - 1 < VIEWARGS then
		refuse(f, pc, "'view' takes the packet and an offset")
	end
	local data, at = state[ins.a + 2], state[ins.a + 3]
	if data == nil or data.t ~= PACKET then
		refuse(f, pc, "'view' takes the packet, not a %s", typename(data))
	end
	if not isinteger(at) then
		refuse(f, pc, "'view' takes an offset, not a %s", typename(at))
	end
	setreg(f, ins.a, fetch(f, ins.a + 3, reg.R1))
	state[ins.a] = {t = VIEW, codec = callee.recv.k}
end

-- a read the kernel's data object publishes, called on the packet
local function accessor(f, pc, ins, state, callee)
	local recv = callee.recv
	local access = recv.t == PACKET and accessors[callee.name]
	if not access then
		refuse(f, pc, "the %s has no method '%s'", typename(recv), callee.name)
	end
	-- getreg takes any word, so an unchecked offset reads where the interpreter would raise
	if ins.b - 1 < ACCESSARGS then
		refuse(f, pc, "'%s' takes an offset", callee.name)
	end
	local at = state[ins.a + 2]
	if not isinteger(at) then
		refuse(f, pc, "'%s' takes a number, not a %s", callee.name, typename(at))
	end
	packetread(f, pc, ins, state, access, callee.name)
end

local function method(f, pc, ins, state, callee)
	local recv = callee.recv
	if recv.t == CTX then
		return contextmethod(f, pc, ins, state, callee)
	end
	if iscodec(recv) then
		return view(f, pc, ins, state, callee)
	end
	accessor(f, pc, ins, state, callee)
end
packet.method = method

-- the field or the bitfield a codec's layout names key, or nil
local function fieldof(codec, key)
	for _, field in ipairs(codec.layout.fields) do
		if field.name == key then
			return field
		end
	end
	for _, field in ipairs(codec.layout.bitfields or {}) do
		if field.name == key then
			return field
		end
	end
end

-- the parameter holding the context or a packet, each the context pointer, which a view, holding its
-- offset alone, is read through: a register past the parameters may be one a single path wrote
local function holder(f, pc, state)
	for i = 0, f.proto.numparams - 1 do
		local value = state[i]
		if value.t == CTX or value.t == PACKET then
			return i
		end
	end
	refuse(f, pc, "a view is read through the context or a packet, which no parameter of the function holds here")
end

-- a field of a view: one packet read, at the view's offset plus the field's, of the field's width or
-- of the load that covers a bitfield, then read as the codec reads it
local function viewfield(f, pc, ins, state, value, key)
	if value.codec == nil then
		refuse(f, pc, "a view here is of more than one struct")
	end
	local field = fieldof(value.codec, key)
	if field == nil then
		refuse(f, pc, "a view has no field '%s'", key)
	end
	if not insn.loadable(field.size) then
		refuse(f, pc, "a view reads 1, 2, 4 or 8 bytes at a time, not %d", field.size)
	end
	packetload(f, pc, holder(f, pc, state), ins.b, field.offset, field, format("field '%s'", key))
	frame.decode(f, state, ins.a, field, key)
end
packet.viewfield = viewfield

return packet

