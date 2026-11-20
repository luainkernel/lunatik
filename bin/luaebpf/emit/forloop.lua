--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The numeric for: its iterations counted up front, as lvm.c's forprep counts them, and a loop the
-- compiler cannot bound counted by the kernel's iterator, with may_goto in its body where the kernel
-- has it.
-- @module luaebpf.emit.forloop

local insn  = require("luaebpf.insn")
local proto = require("luaebpf.proto")
local frame = require("luaebpf.emit.frame")

local INT <const> = frame.INT

local MININT <const> = 1 << 63

local INTSIZE <const> = 4 -- bpf_iter_num_new answers an int, and bpf_iter_num_next points at one

-- what a stop of the kernel's counting logs, where Lua makes every pass and raises nothing
local BUDGET <const> = "'for' outruns the budget the kernel gives it"

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
		f.code:jump(frame.labelof(f, pc + ins.bx + 2))
		frame.reach(f, pc + ins.bx + 2, state)
		return true
	end
	if step > 0 then
		frame.setimm(f, a, udiv(limit - init, step))
	else
		frame.setimm(f, a, udiv(init - limit, -step))
	end
	frame.setimm(f, a + 1, step)
	frame.setimm(f, a + 2, init)
	return false
end

-- as lvm.c's forprep does, the iterations are counted up front, so the loop cannot run past its
-- limit by overflowing it
local function counting(f, pc, ins, state, a)
	local code = f.code
	local skip = frame.labelof(f, pc + ins.bx + 2)
	local descending, divide, store = code:label(), code:label(), code:label()
	frame.into(f, pc, state, a, insn.reg.R1)
	frame.into(f, pc, state, a + 1, insn.reg.R2)
	frame.into(f, pc, state, a + 2, insn.reg.R3)
	if state[a + 2].k == nil then
		code:branchi(insn.jump.JEQ, insn.reg.R3, 0, frame.stop(f, pc, "'for' step is zero"))
	end
	code:alu(insn.alu.MOV, insn.reg.R5, insn.reg.R3)
	code:branchi(insn.jump.JSLT, insn.reg.R3, 0, descending)
	code:branch(insn.jump.JSGT, insn.reg.R1, insn.reg.R2, skip)
	code:alu(insn.alu.SUB, insn.reg.R2, insn.reg.R1)
	code:jump(divide)
	code:place(descending)
	code:branch(insn.jump.JSLT, insn.reg.R1, insn.reg.R2, skip)
	code:alu(insn.alu.MOV, insn.reg.R4, insn.reg.R1)
	code:alu(insn.alu.SUB, insn.reg.R4, insn.reg.R2)
	code:alu(insn.alu.MOV, insn.reg.R2, insn.reg.R4)
	code:neg(insn.reg.R3)
	code:place(divide)
	code:branchi(insn.jump.JEQ, insn.reg.R3, 1, store)
	code:alu(insn.alu.DIV, insn.reg.R2, insn.reg.R3)
	code:place(store)
	frame.setreg(f, a, insn.reg.R1)
	frame.setreg(f, a + 1, insn.reg.R5)
	frame.setreg(f, a + 2, insn.reg.R1)
end

-- the kernel's iterator counts the passes after the first, numbered from 1: the end it takes is an
-- int, so a count no int holds stops the program, and it answers an error past the passes it counts,
-- where the program stops too
local function iterated(f, pc, ins, state, a)
	local code = f.code
	counting(f, pc, ins, state, a)
	code:branchi(insn.jump.JGE, insn.reg.R2, proto.script("linux.limits").int.MAX, frame.stop(f, pc, BUDGET))
	local loop = frame.enter(f, pc, pc + ins.bx + 1)
	code:alu(insn.alu.MOV, insn.reg.R3, insn.reg.R2)
	code:alui(insn.alu.ADD, insn.reg.R3, 1)
	code:set(insn.reg.R2, 1)
	frame.iterate(f, frame.iterator.new, loop)
	frame.extend(f, insn.reg.R0, INTSIZE)
	code:branchi(insn.jump.JNE, insn.reg.R0, 0, frame.stop(f, pc, BUDGET))
end

function forloop.FORPREP(f, pc, ins, state)
	local a = ins.a
	for i = a, a + 2 do
		if not frame.isinteger(state[i]) then
			frame.refuse(f, pc, "'for' takes numbers, not a %s", frame.typename(state[i]))
		end
	end
	if state[a + 2].k == 0 then
		frame.refuse(f, pc, "'for' step is zero")
	end
	local proven = bounded(state, a)
	f.bounded[pc + ins.bx + 1] = proven
	local step = state[a + 2].k
	local never = proven and counted(f, pc, ins, state, a)
	if not never then
		if not proven then
			iterated(f, pc, ins, state, a)
		end
		state[a] = {t = INT}
		state[a + 1] = {t = INT, k = step}
		state[a + 2] = {t = INT}
		frame.reach(f, pc + ins.bx + 2, state)
		frame.reach(f, pc + 1, state)
	end
	return false
end

-- a loop the compiler bounds counts its passes down in its first register, and adds the step to i, as
-- OP_FORLOOP does
local function countdown(f, pc, ins, state)
	local a, code = ins.a, f.code
	frame.into(f, pc, state, a, insn.reg.R1)
	code:branchi(insn.jump.JEQ, insn.reg.R1, 0, frame.labelof(f, pc + 1))
	code:alui(insn.alu.ADD, insn.reg.R1, -1)
	frame.setreg(f, a, insn.reg.R1)
	frame.into(f, pc, state, a + 2, insn.reg.R2)
	code:alu(insn.alu.ADD, insn.reg.R2, frame.getreg(f, pc, state, a + 1, insn.reg.R3))
	frame.setreg(f, a + 2, insn.reg.R2)
	code:jump(frame.labelof(f, pc + 1 - ins.bx))
end

-- the iterator counts the passes of any other, and answers NULL past the last, where it is destroyed
-- and the code after the loop follows. i is the start in the first register plus the step times the
-- pass the iterator answers: an i each pass carries to the next, once the body has made it precise,
-- differs from every pass the verifier walked, which then walks them all
local function iterating(f, pc, ins, state, loop)
	local a, code, done = ins.a, f.code, f.code:label()
	frame.iterate(f, frame.iterator.next, loop)
	code:branchi(insn.jump.JEQ, insn.reg.R0, 0, done)
	if f.unit.maygoto then
		code:maygoto(frame.stop(f, pc, BUDGET)) -- the time the kernel gives a call's loops, where it times them
	end
	code:load(insn.reg.R1, insn.reg.R0, 0, INTSIZE)
	code:alu(insn.alu.MUL, insn.reg.R1, frame.getreg(f, pc, state, a + 1, insn.reg.R2))
	code:alu(insn.alu.ADD, insn.reg.R1, frame.getreg(f, pc, state, a, insn.reg.R2))
	frame.setreg(f, a + 2, insn.reg.R1)
	code:jump(frame.labelof(f, pc + 1 - ins.bx))
	code:place(done)
	frame.iterate(f, frame.iterator.destroy, loop)
end

function forloop.FORLOOP(f, pc, ins, state)
	local a = ins.a
	if f.bounded[pc] then
		countdown(f, pc, ins, state)
	else
		iterating(f, pc, ins, state, f.loops[#f.loops])
	end
	state[a] = {t = INT}
	state[a + 2] = {t = INT}
	frame.reach(f, pc + 1 - ins.bx, state)
	frame.reach(f, pc + 1, state)
	return false
end

return forloop

