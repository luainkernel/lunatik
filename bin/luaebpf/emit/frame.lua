--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- What every lowering shares: the types a Lua register may hold, the words each frame reserves,
-- the abstract state the walk carries along each edge, where a Lua register lives, and the jumps.
-- @module luaebpf.emit.frame

local insn  = require("luaebpf.insn")
local proto = require("luaebpf.proto")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local mathtype   = math.type

local NREGS    <const> = 4   -- Lua registers 0..3 live in r6..r9; the rest spill to the frame
local FIRST    <const> = reg.R6
local SLOT     <const> = 8
local NBITS    <const> = 64
local BYTE     <const> = 8   -- bits

-- the words every frame reserves: the flag a callee raises through the pointer its caller
-- passed, where the callee keeps that pointer, since R1-R5 do not survive a nested call, and
-- the key and the value a map helper is handed by address
local RESERVED <const> = 4
local ABORTED  <const> = -SLOT
local CALLER   <const> = -SLOT * 2
local KEY      <const> = -SLOT * 3
local VALUE    <const> = -SLOT * 4

-- what a Lua register may hold; OTHER is a value the compiler knows and the kernel never sees
local INT     <const> = 1
local BOOL    <const> = 2
local NIL     <const> = 4
local CTX     <const> = 8
local OTHER   <const> = 16
local METHOD  <const> = 32
local PACKET  <const> = 64
local MAYBE   <const> = 128              -- a map value the program has not tested yet
local RECORD  <const> = 256              -- a struct map value, read a field at a time
local RUNTIME <const> = INT | BOOL | NIL -- a value the kernel holds as a word
local PROXY   <const> = CTX | PACKET | MAYBE | RECORD -- a pointer the kernel holds, read through a proxy

local typenames = {[INT] = "number", [BOOL] = "boolean", [NIL] = "nil", [CTX] = "context",
	[METHOD] = "method", [PACKET] = "packet", [MAYBE] = "map value",
	[RECORD] = "struct map value"}

local frame = {
	NREGS = NREGS, SLOT = SLOT, NBITS = NBITS, BYTE = BYTE, RESERVED = RESERVED, ABORTED = ABORTED,
	CALLER = CALLER, KEY = KEY, VALUE = VALUE, INT = INT, BOOL = BOOL, NIL = NIL, CTX = CTX, OTHER = OTHER,
	METHOD = METHOD, PACKET = PACKET, MAYBE = MAYBE, RECORD = RECORD, RUNTIME = RUNTIME, PROXY = PROXY,
	typenames = typenames,
}

local function typename(value)
	if value == nil then
		return "undefined value"
	end
	return typenames[value.t] or "value"
end
frame.typename = typename

local function refuse(f, pc, reason, ...)
	error(format("%s:%d: ", f.chunk, f.proto.lines[pc] or f.proto.linedefined) .. format(reason, ...), 0)
end
frame.refuse = refuse

-- the verifier of a kernel without efficient unaligned access refuses a read wider than a byte at
-- an offset it cannot prove aligned, and the compiler refuses every one there rather than prove
-- which it would take
local function aligned(f, pc, what, size)
	if size > 1 and not f.unit.unaligned then
		refuse(f, pc, "%s reads more than a byte, and this kernel lacks efficient unaligned access", what)
	end
end
frame.aligned = aligned

--- @section the abstract state

-- the join of two abstract values: the types of both, the compile-time value only where every
-- path agrees on it, and the map a lookup came from where the other path agrees on it or is nil
local function join(a, b)
	if a == nil or b == nil then
		return a or b
	end
	if a.t == b.t and a.k == b.k and a.map == b.map then
		return a
	end
	local map = a.map == b.map and a.map or a.t == NIL and b.map or b.t == NIL and a.map or nil
	return {t = a.t | b.t, k = a.k == b.k and a.k or nil, name = a.name == b.name and a.name or nil,
		map = map}
end

local function same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.t == b.t and a.k == b.k and a.map == b.map
end

local function copy(state)
	local out = {}
	for i, value in pairs(state) do
		out[i] = value
	end
	return out
end
frame.copy = copy

-- records the state an edge carries into pc, and notes whether that widened what was there
local function reach(f, pc, state)
	if pc > #f.proto.code then
		return
	end
	local entry = f.entry[pc]
	if entry == nil then
		f.entry[pc] = copy(state)
		f.changed = true
		return
	end
	for i, value in pairs(state) do
		local merged = join(entry[i], value)
		if not same(entry[i], merged) then
			entry[i] = merged
			f.changed = true
		end
	end
end
frame.reach = reach

--- @section Lua registers

local function spilled(i)
	return i >= NREGS
end

local function offset(i)
	return -SLOT * (i - NREGS + 1 + RESERVED)
end

-- the word a Lua register holds, whatever its type
local function fetch(f, i, scratch)
	if spilled(i) then
		f.code:load(scratch, reg.FP, offset(i))
		return scratch
	end
	return FIRST + i
end
frame.fetch = fetch

-- the verifier lets a lookup's pointer be used only where the program has tested it
local function tested(f, pc, value)
	if value ~= nil and (value.t & MAYBE) ~= 0 then
		local name = value.name and format("'%s'", value.name) or "a value"
		refuse(f, pc, "%s may be nil here; test it first", name)
	end
end
frame.tested = tested

local function getreg(f, pc, state, i, scratch)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	tested(f, pc, value)
	if mask == 0 or (mask & ~RUNTIME) ~= 0 then
		refuse(f, pc, "a %s has no value in the kernel here", typename(value))
	end
	return fetch(f, i, scratch)
end
frame.getreg = getreg

local function setreg(f, i, src)
	if spilled(i) then
		f.code:store(reg.FP, offset(i), src)
	else
		f.code:alu(alu.MOV, FIRST + i, src)
	end
end
frame.setreg = setreg

local function setimm(f, i, value)
	if spilled(i) then
		f.code:set(reg.R1, value)
		f.code:store(reg.FP, offset(i), reg.R1)
	else
		f.code:set(FIRST + i, value)
	end
end
frame.setimm = setimm

local function move(f, from, scratch)
	if from ~= scratch then
		f.code:alu(alu.MOV, scratch, from)
	end
	return scratch
end
frame.move = move

-- reads a Lua register into a scratch register the caller may then destroy
local function into(f, pc, state, i, scratch)
	return move(f, getreg(f, pc, state, i, scratch), scratch)
end
frame.into = into

local function isinteger(value)
	return value ~= nil and value.t == INT
end
frame.isinteger = isinteger

-- a value the file body computed becomes a constant of the program; only what the kernel can
-- hold takes a register, and a float, which the body's Lua has and the kernel's does not, is not one
local function resolve(f, pc, state, i, value, name)
	local kind = mathtype(value) or type(value)
	if kind == "integer" then
		setimm(f, i, value)
		state[i] = {t = INT, k = value, name = name}
	elseif kind == "boolean" then
		setimm(f, i, value and 1 or 0)
		state[i] = {t = BOOL, k = value, name = name}
	elseif value == nil then
		setimm(f, i, 0)
		state[i] = {t = NIL, name = name}
	elseif kind == "table" or kind == "function" or kind == "string" then
		state[i] = {t = OTHER, k = value, name = name}
	else
		refuse(f, pc, "'%s' is a %s, which a compiled function cannot hold", name or "value", kind)
	end
end
frame.resolve = resolve

local function constant(f, pc, i)
	if i >= f.proto.nk then
		refuse(f, pc, "constant #%d does not exist", i + 1)
	end
	return f.proto.k[i + 1]
end
frame.constant = constant

-- a shift pair rather than BPF_MEMSX, which the s390 JIT of v6.6 does not take
local function extend(f, dst, size)
	local shift = NBITS - size * BYTE
	f.code:alui(alu.LSH, dst, shift)
	f.code:alui(alu.ARSH, dst, shift)
end
frame.extend = extend

--- @section control flow

local function labelof(f, pc)
	local label = f.labels[pc]
	if label == nil then
		refuse(f, pc, "a jump leaves the function")
	end
	return label
end
frame.labelof = labelof

-- the tail taken where the interpreter would raise: the program's default verdict in its own
-- frame, and the flag that carries the verdict one frame up everywhere else
local function abort(f)
	if f.aborted == nil then
		f.aborted = f.code:label()
	end
	return f.aborted
end
frame.abort = abort

-- a value the program computes past `size` unsigned bytes, fewer than a register holds, takes
-- the default verdict
local function fitsunsigned(f, src, size)
	local code = f.code
	code:alu(alu.MOV, reg.R5, src)
	code:alui(alu.RSH, reg.R5, size * BYTE)
	code:branchi(jump.JNE, reg.R5, 0, abort(f))
end
frame.fitsunsigned = fitsunsigned

local function jumptarget(f, pc)
	local ins = f.proto.code[pc]
	if ins == nil or ins.op ~= opcodes.JMP then
		refuse(f, pc - 1, "a test is not followed by a jump")
	end
	local target = pc + ins.sj + 1
	if target <= pc then
		refuse(f, pc, "'while' and 'repeat' are not compiled yet")
	end
	return target
end
frame.jumptarget = jumptarget

return frame

