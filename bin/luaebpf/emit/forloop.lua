--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The numeric for: its iterations counted up front, as lvm.c's forprep counts them, and a loop the
-- compiler cannot bound guarded by may_goto.
-- @module luaebpf.emit.forloop

local insn  = require("luaebpf.insn")
local frame = require("luaebpf.emit.frame")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local abort, getreg, into, isinteger = frame.abort, frame.getreg, frame.into, frame.isinteger
local labelof, reach, refuse, setimm = frame.labelof, frame.reach, frame.refuse, frame.setimm
local setreg, typename = frame.setreg, frame.typename

local INT <const> = frame.INT

local MININT <const> = 1 << 63

local forloop = {}

-- a bound the compiler proved: the three control registers carry a value it knows, so the count
-- is a constant and the verifier can walk the loop instead of being handed an iteration budget
local function bounded(state, a)
	for i = a, a + 2 do
		local value = state[i]
		if value == nil or value.t ~= INT or value.k == nil then
			return false
		end
	end
	return true
end

local function ult(a, b)
	return (a ~ MININT) < (b ~ MININT)
end

-- the iteration count is unsigned, and Lua's '//' is not; halving first keeps the dividend
-- positive, and one correction step recovers the bit that shifted out
local function udiv(a, b)
	if b < 0 then
		return ult(a, b) and 0 or 1
	end
	if a >= 0 then
		return a // b
	end
	local q = ((a >> 1) // b) << 1
	if not ult(a - q * b, b) then
		q = q + 1
	end
	return q
end

local function counted(f, pc, ins, state, a)
	local init, limit, step = state[a].k, state[a + 1].k, state[a + 2].k
	if (step > 0 and init > limit) or (step < 0 and init < limit) then
		f.code:jump(labelof(f, pc + ins.bx + 2))
		reach(f, pc + ins.bx + 2, state)
		return true
	end
	if step > 0 then
		setimm(f, a, udiv(limit - init, step))
	else
		setimm(f, a, udiv(init - limit, -step))
	end
	setimm(f, a + 1, step)
	setimm(f, a + 2, init)
	return false
end

-- as lvm.c's forprep does, the iterations are counted up front, so the loop cannot run past its
-- limit by overflowing it
local function counting(f, pc, ins, state, a)
	local code = f.code
	local skip = labelof(f, pc + ins.bx + 2)
	local descending, divide, store = code:label(), code:label(), code:label()
	into(f, pc, state, a, reg.R1)
	into(f, pc, state, a + 1, reg.R2)
	into(f, pc, state, a + 2, reg.R3)
	if state[a + 2].k == nil then
		code:branchi(jump.JEQ, reg.R3, 0, abort(f))
	end
	code:alu(alu.MOV, reg.R5, reg.R3)
	code:branchi(jump.JSLT, reg.R3, 0, descending)
	code:branch(jump.JSGT, reg.R1, reg.R2, skip)
	code:alu(alu.SUB, reg.R2, reg.R1)
	code:jump(divide)
	code:place(descending)
	code:branch(jump.JSLT, reg.R1, reg.R2, skip)
	code:alu(alu.MOV, reg.R4, reg.R1)
	code:alu(alu.SUB, reg.R4, reg.R2)
	code:alu(alu.MOV, reg.R2, reg.R4)
	code:neg(reg.R3)
	code:place(divide)
	code:branchi(jump.JEQ, reg.R3, 1, store)
	code:alu(alu.DIV, reg.R2, reg.R3)
	code:place(store)
	setreg(f, a, reg.R2)
	setreg(f, a + 1, reg.R5)
	setreg(f, a + 2, reg.R1)
end

function forloop.FORPREP(f, pc, ins, state)
	local a = ins.a
	for i = a, a + 2 do
		if not isinteger(state[i]) then
			refuse(f, pc, "'for' takes numbers, not a %s", typename(state[i]))
		end
	end
	if state[a + 2].k == 0 then
		refuse(f, pc, "'for' step is zero")
	end
	local proven = bounded(state, a)
	f.bounded[pc + ins.bx + 1] = proven
	local step = state[a + 2].k
	local never = proven and counted(f, pc, ins, state, a)
	if not never then
		if not proven then
			counting(f, pc, ins, state, a)
		end
		state[a] = {t = INT}
		state[a + 1] = {t = INT, k = step}
		state[a + 2] = {t = INT}
		reach(f, pc + ins.bx + 2, state)
		reach(f, pc + 1, state)
	end
	return false
end

function forloop.FORLOOP(f, pc, ins, state)
	local a, code = ins.a, f.code
	local after = labelof(f, pc + 1)
	if not f.bounded[pc] then
		if not f.unit.maygoto then
			refuse(f, pc, "a 'for' the compiler cannot bound needs may_goto, which this kernel lacks")
		end
		if f.drop ~= "maygoto" then
			code:maygoto(after)
		end
	end
	into(f, pc, state, a, reg.R1)
	code:branchi(jump.JEQ, reg.R1, 0, after)
	code:alui(alu.ADD, reg.R1, -1)
	setreg(f, a, reg.R1)
	into(f, pc, state, a + 2, reg.R2)
	code:alu(alu.ADD, reg.R2, getreg(f, pc, state, a + 1, reg.R3))
	setreg(f, a + 2, reg.R2)
	code:jump(labelof(f, pc + 1 - ins.bx))
	state[a] = {t = INT}
	state[a + 2] = {t = INT}
	reach(f, pc + 1 - ins.bx, state)
	reach(f, pc + 1, state)
	return false
end

return forloop

