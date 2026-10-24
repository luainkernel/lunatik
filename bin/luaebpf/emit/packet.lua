--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The packet proxy: the reads the kernel's data object publishes, each held to the packet's bounds,
-- its length, and the dispatch of a method called on either proxy.
-- @module luaebpf.emit.packet

local insn    = require("luaebpf.insn")
local frame   = require("luaebpf.emit.frame")
local context = require("luaebpf.emit.context")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local format = string.format
local abort, aligned, extend, fetch, into = frame.abort, frame.aligned, frame.extend, frame.fetch, frame.into
local isinteger, refuse, setreg, typename = frame.isinteger, frame.refuse, frame.setreg, frame.typename
local contextcall, layout = context.contextcall, context.layout

local BYTE   <const> = frame.BYTE
local CTX    <const> = context.CTX
local INT    <const> = frame.INT
local NBITS  <const> = frame.NBITS
local PACKET <const> = frame.type("packet", "proxy")

-- MAX_PACKET_OFF: the verifier refuses arithmetic between a packet pointer and a register whose
-- range it does not know, and find_good_pkt_pointers leaves a pointer no range at all once the
-- offset's maximum plus the access would carry it past this. So an access tests its offset
-- against the last one its width can start at. Anything above is out of bounds on every packet
-- BPF_PROG_TEST_RUN or a NIC can build, and the interpreter raises there too.
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

local packet = {PACKET = PACKET}

-- data and data_end, which the kernel rewrites a four-byte context load of into a full pointer
local function bounds(f)
	local packet, fields = f.unit.context.packet, layout(f)
	return fields[packet.base], fields[packet.limit]
end

-- One access, self-contained: data and data_end are re-read from the context rather than kept
-- live, so the proxy is one register that survives a call and cannot go stale.
local function packetread(f, pc, ins, state, access)
	local code, base, limit = f.code, bounds(f)
	into(f, pc, state, ins.a + 2, reg.R4)
	local ptr = fetch(f, ins.a + 1, reg.R3)
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
	if access.signed and access.size * BYTE < NBITS then
		extend(f, reg.R1, access.size)
	end
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

local function span(f, ptr)
	local code, base, limit = f.code, bounds(f)
	code:load(reg.R1, ptr, base.offset, base.size)
	code:load(reg.R2, ptr, limit.offset, limit.size)
	code:alu(alu.SUB, reg.R2, reg.R1)
	return reg.R2
end

-- the length is the distance between the bounds, which is what '#' on the kernel's data object
-- answers and what the interpreted twin reads off the same bytes
local function packetlen(f, ins, state)
	setreg(f, ins.a, span(f, fetch(f, ins.b, reg.R3)))
	state[ins.a] = {t = INT}
end
packet.packetlen = packetlen

-- data_end ends the linear head (bpf_compute_data_pointers): a packet longer than the span is not linear
local function checklinear(f, ctx)
	local length = layout(f)[f.unit.context.length]
	local head = span(f, ctx)
	f.code:load(reg.R1, ctx, length.offset, length.size)
	f.code:branch(jump.JNE, reg.R1, head, abort(f))
end

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
	if packet.linear then
		checklinear(f, ctx)
	end
	setreg(f, ins.a, ctx)
	state[ins.a] = {t = PACKET, name = name}
end

local function contextmethod(f, pc, ins, state, callee)
	if callee.name == f.unit.context.packet.method then
		return contextpacket(f, pc, ins, state, callee.name)
	end
	contextcall(f, pc, ins, state, callee.name)
end

local function method(f, pc, ins, state, callee)
	local recv = callee.recv
	if recv.t == CTX then
		return contextmethod(f, pc, ins, state, callee)
	end
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
	aligned(f, pc, format("'%s'", callee.name), access.size)
	packetread(f, pc, ins, state, access)
end
packet.method = method

return packet

