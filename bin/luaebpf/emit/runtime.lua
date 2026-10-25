--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A call into the kernel Lua runtime: the kfunc of the program's type, handed the runtime's key,
-- the arguments and the context, and the answer it returns, which the program tests before it reads.
-- @module luaebpf.emit.runtime

local insn    = require("luaebpf.insn")
local frame   = require("luaebpf.emit.frame")
local context = require("luaebpf.emit.context")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local format = string.format
local unpack = string.unpack
local insert = table.insert
local copy, depth, extend, fetch, getreg = frame.copy, frame.depth, frame.extend, frame.fetch, frame.getreg
local isinteger, jumptarget, labelof, move = frame.isinteger, frame.jumptarget, frame.labelof, frame.move
local reach, refuse, setimm, setreg = frame.reach, frame.refuse, frame.setimm, frame.setreg
local stack, typename = frame.stack, frame.typename

local ANSWER <const> = frame.type("runtime answer", "word", "untested")
local CTX    <const> = context.CTX
local INT    <const> = frame.INT
local NIL    <const> = frame.NIL
local SLOT   <const> = frame.SLOT

local CTXREG  <const> = 0  -- the program's parameter, which the call passes as the context
local NUL     <const> = 1  -- the byte key__sz counts past the key, which the kfunc writes in place
local INTSIZE <const> = 4  -- the kfunc answers an int
local ABSENT  <const> = -1 -- what the kfunc answers where Lua answers nil (luakfunc_action)

local runtime = {ANSWER = ANSWER}

local function named(value, otherwise)
	return value.name and format("'%s'", value.name) or otherwise
end

-- the key's bytes NUL-padded to whole words, each read in the byte order a store writes it in
local function keywords(f, key)
	local count = (#key + NUL + SLOT - 1) // SLOT
	local padded = key .. ("\0"):rep(count * SLOT - #key)
	local order = (f.unit.bigendian and ">" or "<") .. "i8"
	local words = {}
	for i = 1, count do
		insert(words, (unpack(order, padded, (i - 1) * SLOT + 1)))
	end
	return words
end

local function arguments(f, pc, ins, state)
	for i = 1, ins.b - 1 do
		local value = state[ins.a + i]
		if not isinteger(value) then
			refuse(f, pc, "argument #%d is a %s, and a call into the runtime passes numbers", i, typename(value))
		end
	end
	return ins.b - 1
end

-- the kfunc reads the key and the arguments by address, so both go below the frame, where no Lua
-- register lives and nothing outlives the call
function runtime.call(f, pc, ins, state, callee)
	if not f.isprogram then
		refuse(f, pc, "%s can only be called from the program's own function", named(callee, "a runtime"))
	end
	local ctx = state[CTXREG]
	if ctx == nil or ctx.t ~= CTX then
		refuse(f, pc, "a call into the runtime passes the context, which the program's parameter does not hold")
	end
	local code, key, nargs = f.code, callee.k.key, arguments(f, pc, ins, state)
	local words = keywords(f, key)
	local bottom = depth(f) + (#words + nargs) * SLOT
	stack(f, pc, bottom)
	local at, args = -bottom, -bottom + #words * SLOT
	for i, word in ipairs(words) do
		code:set(reg.R1, word)
		code:store(reg.FP, at + (i - 1) * SLOT, reg.R1)
	end
	for i = 1, nargs do
		code:store(reg.FP, args + (i - 1) * SLOT, getreg(f, pc, state, ins.a + i, reg.R1))
	end
	code:alu(alu.MOV, reg.R1, reg.FP)
	code:alui(alu.ADD, reg.R1, at)
	code:set(reg.R2, #key + NUL)
	move(f, fetch(f, CTXREG, reg.R3), reg.R3)
	if nargs == 0 then
		code:set(reg.R4, 0) -- the verifier takes a null pointer where the size is zero
	else
		code:alu(alu.MOV, reg.R4, reg.FP)
		code:alui(alu.ADD, reg.R4, args)
	end
	code:set(reg.R5, nargs * SLOT)
	code:kfunc(f.unit.kfunc)
	insert(f.calls, {line = f.proto.lines[pc], key = key})
	if ins.c > 1 then
		extend(f, reg.R0, INTSIZE)
		setreg(f, ins.a, reg.R0)
		state[ins.a] = {t = ANSWER, name = callee.name}
	end
end

-- whether a register holds what a call answered, alone or joined with another type
function runtime.answers(value)
	return value ~= nil and (value.t & ANSWER) ~= 0
end

-- 'if v then' and 'v == nil' compare the answer with the kfunc's -1, and the arm that finds it
-- stores the zero word nil is everywhere else; onnil is whether the opcode's jump is taken on nil
function runtime.test(f, pc, ins, state, onnil)
	local code, value = f.code, state[ins.a]
	if value.t ~= ANSWER then
		refuse(f, pc, "%s joined another value here, whose nil is 0 and not -1; test it before the paths join",
			named(value, "a runtime answer"))
	end
	local target = jumptarget(f, pc + 1)
	local number = onnil and pc + 2 or target
	local absent = onnil and target or pc + 2
	local missing = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), ABSENT, missing)
	local taken = copy(state)
	taken[ins.a] = {t = INT, name = value.name}
	code:jump(labelof(f, number))
	reach(f, number, taken)
	code:place(missing)
	setimm(f, ins.a, 0)
	code:jump(labelof(f, absent))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, absent, state)
	return false
end

return runtime

