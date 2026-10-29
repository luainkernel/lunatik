--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The comparisons, TEST, TESTSET and JMP: a test whose outcome the types decide is the jump or
-- nothing, and any other a conditional jump.
-- @module luaebpf.emit.branch

local insn       = require("luaebpf.insn")
local frame      = require("luaebpf.emit.frame")
local arithmetic = require("luaebpf.emit.arithmetic")
local loads      = require("luaebpf.emit.loads")
local map        = require("luaebpf.emit.map")
local runtime    = require("luaebpf.emit.runtime")

local jump, reg = insn.jump, insn.reg
local constant, copy, getreg, into = frame.constant, frame.copy, frame.getreg, frame.into
local isinteger, jumptarget, labelof, reach = frame.isinteger, frame.jumptarget, frame.labelof, frame.reach
local refuse, setreg, tested, typename = frame.refuse, frame.setreg, frame.tested, frame.typename
local truth = arithmetic.truth
local moveslot = loads.moveslot
local testlookup = map.testlookup
local answers, testanswer = runtime.answers, runtime.test

local BOOL  <const> = frame.BOOL
local INT   <const> = frame.INT
local MAYBE <const> = map.MAYBE
local NIL   <const> = frame.NIL
local OTHER <const> = frame.OTHER

local branch = {}

local relations = {
	EQ = {[true] = jump.JEQ, [false] = jump.JNE},
	LT = {[true] = jump.JSLT, [false] = jump.JSGE},
	LE = {[true] = jump.JSLE, [false] = jump.JSGT},
	GT = {[true] = jump.JSGT, [false] = jump.JSLE},
	GE = {[true] = jump.JSGE, [false] = jump.JSLT},
}

-- a test whose outcome the types already decide is the jump, or nothing at all
local function settled(f, pc, state, taken)
	if not taken then
		reach(f, pc + 2, state)
		return false
	end
	local target = jumptarget(f, pc + 1)
	f.code:jump(labelof(f, target))
	reach(f, target, state)
	return false
end

local function testjump(f, pc, state, op, dst, src)
	local target = jumptarget(f, pc + 1)
	f.code:branch(op, dst, src, labelof(f, target))
	reach(f, target, state)
	reach(f, pc + 2, state)
	return false
end

local function ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		return
	end
	if not isinteger(a) or not isinteger(b) then
		refuse(f, pc, "attempt to compare a %s with a %s", typename(a), typename(b))
	end
end

-- whether the type names one Lua type. A join widens a register to several, and the bits say
-- which for none of them: false, nil and the integer zero are one word.
local function exact(value)
	local mask = value ~= nil and value.t or 0
	return mask ~= 0 and (mask & (mask - 1)) == 0
end

-- whether the compiler holds the value itself, rather than the register
local function held(value)
	return value ~= nil and (value.k ~= nil or value.t == NIL)
end

-- the type mask of a bytecode constant
local function typeof(value)
	local kind = type(value)
	if kind == "number" then
		return INT
	end
	if kind == "boolean" then
		return BOOL
	end
	if value == nil then
		return NIL
	end
	return OTHER
end

local function undecidable(f, pc, a, b)
	refuse(f, pc, "a %s cannot be compared with a %s here", typename(a), typename(b))
end

-- the answer Lua's '==' is pinned to, and nil where the registers carry it
local function equality(f, pc, a, b)
	tested(f, pc, a)
	tested(f, pc, b)
	if exact(a) and exact(b) then
		if a.t ~= b.t then
			return false -- Lua's '==' is false across types
		end
		if a.t == INT or a.t == BOOL then
			return nil
		end
	end
	if held(a) and held(b) then
		return a.k == b.k
	end
	undecidable(f, pc, a, b)
end

local function compare(f, pc, ins, state, relation, b)
	local a = state[ins.a]
	ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		local answer = equality(f, pc, a, b)
		if answer ~= nil then
			return settled(f, pc, state, answer == ins.k)
		end
	end
	into(f, pc, state, ins.a, reg.R1)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1, getreg(f, pc, state, ins.b, reg.R2))
end

function branch.EQ(f, pc, ins, state) return compare(f, pc, ins, state, "EQ", state[ins.b]) end
function branch.LT(f, pc, ins, state) return compare(f, pc, ins, state, "LT", state[ins.b]) end
function branch.LE(f, pc, ins, state) return compare(f, pc, ins, state, "LE", state[ins.b]) end

local function compareconst(f, pc, ins, state, relation, value)
	local a, b = state[ins.a], {t = typeof(value), k = value}
	if relation == "EQ" and b.t == NIL and answers(a) then
		return testanswer(f, pc, ins, state, ins.k)
	end
	ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		local answer = equality(f, pc, a, b)
		if answer ~= nil then
			return settled(f, pc, state, answer == ins.k)
		end
	end
	local operand = value
	if b.t == BOOL then -- the register carries the 1 or 0 'resolve' stored for it
		operand = value and 1 or 0
	end
	into(f, pc, state, ins.a, reg.R1)
	f.code:set(reg.R2, operand)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1, reg.R2)
end

function branch.EQI(f, pc, ins, state) return compareconst(f, pc, ins, state, "EQ", ins.sb) end
function branch.LTI(f, pc, ins, state) return compareconst(f, pc, ins, state, "LT", ins.sb) end
function branch.LEI(f, pc, ins, state) return compareconst(f, pc, ins, state, "LE", ins.sb) end
function branch.GTI(f, pc, ins, state) return compareconst(f, pc, ins, state, "GT", ins.sb) end
function branch.GEI(f, pc, ins, state) return compareconst(f, pc, ins, state, "GE", ins.sb) end

function branch.EQK(f, pc, ins, state)
	return compareconst(f, pc, ins, state, "EQ", constant(f, pc, ins.b))
end

function branch.TEST(f, pc, ins, state)
	local value = state[ins.a]
	-- a register nil on one path holds 0 there, the word a lookup that found nothing leaves
	if value ~= nil and value.t | NIL == MAYBE | NIL then
		return testlookup(f, pc, ins, state)
	end
	if answers(value) then
		return testanswer(f, pc, ins, state, not ins.k)
	end
	local known = truth(f, pc, state, ins.a)
	if known ~= nil then
		return settled(f, pc, state, known == ins.k)
	end
	into(f, pc, state, ins.a, reg.R1)
	f.code:set(reg.R2, 0)
	return testjump(f, pc, state, relations.EQ[not ins.k], reg.R1, reg.R2)
end

function branch.TESTSET(f, pc, ins, state)
	local known = truth(f, pc, state, ins.b)
	if known ~= nil then
		if known ~= ins.k then
			reach(f, pc + 2, state)
			return false
		end
		moveslot(f, state, ins.a, ins.b)
		local target = jumptarget(f, pc + 1)
		f.code:jump(labelof(f, target))
		reach(f, target, state)
		return false
	end
	local skip = f.code:label()
	into(f, pc, state, ins.b, reg.R1)
	f.code:branchi(ins.k and jump.JEQ or jump.JNE, reg.R1, 0, skip)
	local taken = copy(state)
	setreg(f, ins.a, reg.R1)
	taken[ins.a] = state[ins.b]
	local target = jumptarget(f, pc + 1)
	f.code:jump(labelof(f, target))
	f.code:place(skip)
	reach(f, target, taken)
	reach(f, pc + 2, state)
	return false
end

function branch.JMP(f, pc, _, state)
	local target = jumptarget(f, pc)
	f.code:jump(labelof(f, target))
	reach(f, target, state)
	return false
end

return branch

