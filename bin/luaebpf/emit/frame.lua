--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- What every lowering shares: the declaration of a type a Lua register may hold, and the four
-- `resolve` gives, the words each frame reserves, the abstract state the walk carries along each
-- edge, where a Lua register lives, and the jumps.
-- @module luaebpf.emit.frame

local insn  = require("luaebpf.insn")
local proto = require("luaebpf.proto")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local mathtype   = math.type
local max        = math.max

local NREGS    <const> = 4   -- Lua registers 0..3 live in r6..r9; the rest spill to the frame
local FIRST    <const> = reg.R6
local SLOT     <const> = 8
local NBITS    <const> = 64
local BYTE     <const> = 8   -- bits
local MAXSTACK <const> = 512 -- MAX_BPF_STACK

-- the words every frame reserves: the flag a callee raises through the pointer its caller
-- passed, where the callee keeps that pointer, since R1-R5 do not survive a nested call, and
-- the key and the value a map helper is handed by address
local RESERVED <const> = 4
local ABORTED  <const> = -SLOT
local CALLER   <const> = -SLOT * 2
local KEY      <const> = -SLOT * 3
local VALUE    <const> = -SLOT * 4

local typenames = {}

-- the masks the frame's checks read, widened by each lowering that declares a type into one, so a
-- reader takes the field where it uses it and never copies it into a local
local classes = {
	word     = 0, -- a value the kernel holds as a word
	proxy    = 0, -- a pointer the kernel holds, read through a proxy
	untested = 0, -- a word the program must test before the kernel reads it
}

local nextbit = 1

-- what a Lua register may hold, a bit each, declared by the lowering whose code first gives a
-- register that type, so a construct adds its own without editing a list every lowering shares
local function newtype(name, ...)
	local bit = nextbit
	nextbit = bit << 1
	typenames[bit] = name
	for _, class in ipairs({...}) do
		if classes[class] == nil then
			error(format("'%s' is not a class the frame reads", class), 2)
		end
		classes[class] = classes[class] | bit
	end
	return bit
end

local INT  <const> = newtype("number", "word")
local BOOL <const> = newtype("boolean", "word")
local NIL  <const> = newtype("nil", "word")

-- a value the compiler knows and the kernel never sees
local OTHER <const> = newtype("value")

local frame = {
	NREGS = NREGS, SLOT = SLOT, NBITS = NBITS, BYTE = BYTE, RESERVED = RESERVED, ABORTED = ABORTED,
	CALLER = CALLER, KEY = KEY, VALUE = VALUE, INT = INT, BOOL = BOOL, NIL = NIL, OTHER = OTHER,
	classes = classes, type = newtype, typenames = typenames,
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

-- the bytes a frame holds: the words it reserves and the Lua registers that spill below them
local function depth(f)
	return (max(f.proto.maxstacksize - NREGS, 0) + RESERVED) * SLOT
end
frame.depth = depth

-- a frame deeper than eBPF allows is refused at the line that needs it
local function stack(f, pc, bytes)
	if bytes > MAXSTACK then
		refuse(f, pc, "the function needs %d bytes of stack, over the %d eBPF allows", bytes, MAXSTACK)
	end
end
frame.stack = stack

-- the word a Lua register holds, whatever its type
local function fetch(f, i, scratch)
	if spilled(i) then
		f.code:load(scratch, reg.FP, offset(i))
		return scratch
	end
	return FIRST + i
end
frame.fetch = fetch

-- the value's name quoted, or what the caller says of one with none
local function named(value, otherwise)
	return value.name and format("'%s'", value.name) or otherwise
end
frame.named = named

-- the verifier lets a lookup's pointer be used only where the program has tested it
local function tested(f, pc, value)
	if value ~= nil and (value.t & classes.untested) ~= 0 then
		refuse(f, pc, "%s may be nil here; test it first", named(value, "a value"))
	end
end
frame.tested = tested

local function getreg(f, pc, state, i, scratch)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	tested(f, pc, value)
	if mask == 0 or (mask & ~classes.word) ~= 0 then
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

-- the test of a word the kernel answered against `word`, its nil: `found` narrows the register on the
-- arm that found another, the other arm holds nil's zero word, and `taken` is whether the opcode's
-- jump is the former
local function narrow(f, pc, ins, state, word, taken, found)
	local code, value = f.code, state[ins.a]
	local target = jumptarget(f, pc + 1)
	local hit = taken and target or pc + 2
	local miss = taken and pc + 2 or target
	local absent = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), word, absent)
	local narrowed = copy(state)
	found(f, pc, narrowed, ins.a, value)
	code:jump(labelof(f, hit))
	reach(f, hit, narrowed)
	code:place(absent)
	if word ~= 0 then
		setimm(f, ins.a, 0)
	end
	code:jump(labelof(f, miss))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, miss, state)
	return false
end
frame.narrow = narrow

return frame

