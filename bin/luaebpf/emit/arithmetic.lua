--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The arithmetic opcodes, with Lua's semantics over 64-bit integers: floor division and modulo, the
-- shifts, the unary operators and NOT, and the truth of a register as Lua reads it.
-- @module luaebpf.emit.arithmetic

local insn  = require("luaebpf.insn")
local frame = require("luaebpf.emit.frame")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local abort, constant, into, isinteger = frame.abort, frame.constant, frame.into, frame.isinteger
local refuse, resolve, setreg, typename = frame.refuse, frame.resolve, frame.setreg, frame.typename

local BOOL  <const> = frame.BOOL
local INT   <const> = frame.INT
local MAYBE <const> = frame.MAYBE
local NBITS <const> = frame.NBITS
local NIL   <const> = frame.NIL

local arithmetic = {}

-- Lua's floor division: the quotient is corrected toward minus infinity when the operands'
-- signs differ, a divisor of -1 is a negation (which mininteger needs), and a divisor of zero
-- raises, so the program takes its default verdict
local function floordiv(f)
	local code = f.code
	local negate, done = code:label(), code:label()
	if f.drop ~= "divisor" then
		code:branchi(jump.JEQ, reg.R2, 0, abort(f))
	end
	code:branchi(jump.JEQ, reg.R2, -1, negate)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:alu(alu.MOV, reg.R4, reg.R1)
	code:sdiv(alu.MOD, reg.R4, reg.R2)
	code:sdiv(alu.DIV, reg.R1, reg.R2)
	code:branchi(jump.JEQ, reg.R4, 0, done)
	code:alu(alu.XOR, reg.R3, reg.R2)
	code:branchi(jump.JSGE, reg.R3, 0, done)
	code:alui(alu.ADD, reg.R1, -1)
	code:jump(done)
	code:place(negate)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:set(reg.R1, 0)
	code:alu(alu.SUB, reg.R1, reg.R3)
	code:place(done)
end

-- Lua's modulo: the remainder takes the divisor's sign, and a divisor of -1 is zero
local function floormod(f)
	local code = f.code
	local zero, done = code:label(), code:label()
	if f.drop ~= "divisor" then
		code:branchi(jump.JEQ, reg.R2, 0, abort(f))
	end
	code:branchi(jump.JEQ, reg.R2, -1, zero)
	code:sdiv(alu.MOD, reg.R1, reg.R2)
	code:branchi(jump.JEQ, reg.R1, 0, done)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:alu(alu.XOR, reg.R3, reg.R2)
	code:branchi(jump.JSGE, reg.R3, 0, done)
	code:alu(alu.ADD, reg.R1, reg.R2)
	code:jump(done)
	code:place(zero)
	code:set(reg.R1, 0)
	code:place(done)
end

-- luaV_shiftl: logical in both directions, zero past the word, and a negative count shifts the
-- other way; eBPF masks the count to 63, so the range is tested rather than trusted
local function shiftl(f)
	local code = f.code
	local right, zero, done = code:label(), code:label(), code:label()
	code:branchi(jump.JSLT, reg.R2, 0, right)
	code:branchi(jump.JSGE, reg.R2, NBITS, zero)
	code:alu(alu.LSH, reg.R1, reg.R2)
	code:jump(done)
	code:place(right)
	code:branchi(jump.JSLE, reg.R2, -NBITS, zero)
	code:neg(reg.R2)
	code:alu(alu.RSH, reg.R1, reg.R2)
	code:jump(done)
	code:place(zero)
	code:set(reg.R1, 0)
	code:place(done)
end

-- every binary operator over R1 and R2, leaving the result in R1
local binops = {}

function binops.ADD(f) f.code:alu(alu.ADD, reg.R1, reg.R2) end
function binops.SUB(f) f.code:alu(alu.SUB, reg.R1, reg.R2) end
function binops.MUL(f) f.code:alu(alu.MUL, reg.R1, reg.R2) end
function binops.BAND(f) f.code:alu(alu.AND, reg.R1, reg.R2) end
function binops.BOR(f) f.code:alu(alu.OR, reg.R1, reg.R2) end
function binops.BXOR(f) f.code:alu(alu.XOR, reg.R1, reg.R2) end
function binops.IDIV(f) floordiv(f) end
function binops.MOD(f) floormod(f) end
function binops.SHL(f) shiftl(f) end

function binops.SHR(f)
	f.code:neg(reg.R2)
	shiftl(f)
end

-- the kernel calls no metamethod, so every operand an arithmetic opcode reads is a number
local function numbers(f, pc, ...)
	for _, value in ipairs({...}) do
		if not isinteger(value) then
			refuse(f, pc, "attempt to perform arithmetic on a %s value", typename(value))
		end
	end
end

-- R[A] := R[B] op R[C], and R[A] := R[B] op <constant>; a constant takes a register too, since
-- eBPF's immediate is 32 bits and Lua's constants are not
local function register(f, pc, ins, state, op)
	into(f, pc, state, ins.b, reg.R1)
	into(f, pc, state, ins.c, reg.R2)
	numbers(f, pc, state[ins.b], state[ins.c])
	binops[op](f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

local function immediate(f, pc, ins, state, op, value)
	into(f, pc, state, ins.b, reg.R1)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R2, value)
	binops[op](f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

local function numeric(f, pc, value)
	if type(value) ~= "number" then
		refuse(f, pc, "attempt to perform arithmetic on a %s constant", type(value))
	end
	return value
end

function arithmetic.ADD(f, pc, ins, state) register(f, pc, ins, state, "ADD") end
function arithmetic.SUB(f, pc, ins, state) register(f, pc, ins, state, "SUB") end
function arithmetic.MUL(f, pc, ins, state) register(f, pc, ins, state, "MUL") end
function arithmetic.MOD(f, pc, ins, state) register(f, pc, ins, state, "MOD") end
function arithmetic.IDIV(f, pc, ins, state) register(f, pc, ins, state, "IDIV") end
function arithmetic.BAND(f, pc, ins, state) register(f, pc, ins, state, "BAND") end
function arithmetic.BOR(f, pc, ins, state) register(f, pc, ins, state, "BOR") end
function arithmetic.BXOR(f, pc, ins, state) register(f, pc, ins, state, "BXOR") end
function arithmetic.SHL(f, pc, ins, state) register(f, pc, ins, state, "SHL") end
function arithmetic.SHR(f, pc, ins, state) register(f, pc, ins, state, "SHR") end

function arithmetic.ADDK(f, pc, ins, state)
	immediate(f, pc, ins, state, "ADD", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.SUBK(f, pc, ins, state)
	immediate(f, pc, ins, state, "SUB", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.MULK(f, pc, ins, state)
	immediate(f, pc, ins, state, "MUL", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.MODK(f, pc, ins, state)
	immediate(f, pc, ins, state, "MOD", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.IDIVK(f, pc, ins, state)
	immediate(f, pc, ins, state, "IDIV", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.BANDK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BAND", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.BORK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BOR", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.BXORK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BXOR", numeric(f, pc, constant(f, pc, ins.c)))
end

function arithmetic.ADDI(f, pc, ins, state)
	immediate(f, pc, ins, state, "ADD", ins.sc)
end

-- the constant is the left operand of a SHLI, and a SHRI's count is negated into a shift left
function arithmetic.SHLI(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R2)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R1, ins.sc)
	shiftl(f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

function arithmetic.SHRI(f, pc, ins, state)
	immediate(f, pc, ins, state, "SHL", -ins.sc)
end

function arithmetic.UNM(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R2)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R1, 0)
	f.code:alu(alu.SUB, reg.R1, reg.R2)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

function arithmetic.BNOT(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R1)
	numbers(f, pc, state[ins.b])
	f.code:alui(alu.XOR, reg.R1, -1)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

-- the truth of a register as Lua reads it: 0 is true, and only false and nil are not. nil when
-- the types leave it to a test at run time.
local function truth(f, pc, state, i)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	if mask == INT then
		return true
	end
	if mask == NIL then
		return false
	end
	if mask == 0 or (mask & ~(BOOL | NIL | MAYBE)) ~= 0 then
		refuse(f, pc, "a %s has no truth value in a compiled function", typename(value))
	end
	return nil
end
arithmetic.truth = truth

function arithmetic.NOT(f, pc, ins, state)
	local known = truth(f, pc, state, ins.b)
	if known ~= nil then
		resolve(f, pc, state, ins.a, not known)
		return
	end
	local one, done = f.code:label(), f.code:label()
	into(f, pc, state, ins.b, reg.R1)
	f.code:branchi(jump.JEQ, reg.R1, 0, one)
	f.code:set(reg.R2, 0)
	f.code:jump(done)
	f.code:place(one)
	f.code:set(reg.R2, 1)
	f.code:place(done)
	setreg(f, ins.a, reg.R2)
	state[ins.a] = {t = BOOL}
end

-- the metamethod opcode, which the VM skips when both operands were numbers; 'numbers' reads
-- them where they are still live, since the opcode before this one writes over one of them
local function skipped() end

arithmetic.MMBIN, arithmetic.MMBINI, arithmetic.MMBINK = skipped, skipped, skipped

return arithmetic

