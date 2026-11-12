--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A call into the kernel Lua runtime, through the run method SELF reads off it: the kfunc of the
-- program's type, handed the runtime's key, the arguments and the context, and the answer it
-- returns, which the program tests before it reads.
-- @module luaebpf.emit.runtime

local insn    = require("luaebpf.insn")
local frame   = require("luaebpf.emit.frame")
local context = require("luaebpf.emit.context")

local unpack = string.unpack
local insert = table.insert

local ANSWER <const> = frame.type("runtime answer", "word", "untested")
local RUN    <const> = frame.type("runtime method")

local CTXREG  <const> = 0  -- the program's parameter, which the call passes as the context
local NUL     <const> = 1  -- the byte key__sz counts past the key, which the kfunc writes in place
local INTSIZE <const> = 4  -- the kfunc answers an int
local ABSENT  <const> = -1 -- what the kfunc answers where Lua answers nil (luakfunc_action)
local SELFREG <const> = 1  -- SELF puts the runtime past the method, and the arguments past it

local proxy = {} -- no method: it marks what lunatik.runtime returns, which SELF and CALL look for

local runtime = {ANSWER = ANSWER, proxy = proxy}

-- whether a value the file body computed is a runtime lunatik.runtime returned
function runtime.isproxy(value)
	return getmetatable(value) == proxy
end

-- the key's bytes NUL-padded to whole words, each read in the byte order a store writes it in
local function keywords(f, key)
	local count = (#key + NUL + frame.SLOT - 1) // frame.SLOT
	local padded = key .. ("\0"):rep(count * frame.SLOT - #key)
	local order = (f.unit.bigendian and ">" or "<") .. "i8"
	local words = {}
	for i = 1, count do
		insert(words, (unpack(order, padded, (i - 1) * frame.SLOT + 1)))
	end
	return words
end

-- the call a refusal tells the program to write
local function written(value)
	return string.format("'%s:run(...)'", value.name or "runtime")
end

-- 'r:run' reads the one method a runtime has, the kfunc's own verb; r goes to A+1, as SELF puts any
-- receiver, a value the kernel never sees
function runtime.self(f, pc, ins, state)
	local recv = state[ins.b]
	local name = frame.constant(f, pc, ins.c)
	if name ~= "run" then
		frame.refuse(f, pc, "a runtime has no method '%s'; write %s", name, written(recv))
	end
	state[ins.a + SELFREG] = recv
	state[ins.a] = {t = RUN, k = recv.k, name = recv.name}
end

local function arguments(f, pc, ins, state)
	local nargs = ins.b - 1 - SELFREG
	for i = 1, nargs do
		local value = state[ins.a + SELFREG + i]
		if not frame.isinteger(value) then
			frame.refuse(f, pc, "argument #%d is a %s, and a call into the runtime passes numbers", i,
				frame.typename(value))
		end
	end
	return nargs
end

local function placed(f, pc, state, callee)
	if not f.isprogram then
		frame.refuse(f, pc, "%s can only be called from the program's own function", frame.named(callee, "a runtime"))
	end
	local ctx = state[CTXREG]
	if ctx == nil or ctx.t ~= context.CTX then
		frame.refuse(f, pc, "a call into the runtime passes the context, which the program's parameter does not hold")
	end
end

-- the kfunc reads the key and the arguments by address, so both go below the frame, where no Lua
-- register lives and nothing outlives the call
local function stage(f, pc, ins, state, key, nargs)
	local code, words = f.code, keywords(f, key)
	local bottom = frame.depth(f) + (#words + nargs) * frame.SLOT
	frame.stack(f, pc, bottom)
	local at, args = -bottom, -bottom + #words * frame.SLOT
	for i, word in ipairs(words) do
		code:set(insn.reg.R1, word)
		code:store(insn.reg.FP, at + (i - 1) * frame.SLOT, insn.reg.R1)
	end
	for i = 1, nargs do
		code:store(insn.reg.FP, args + (i - 1) * frame.SLOT,
			frame.getreg(f, pc, state, ins.a + SELFREG + i, insn.reg.R1))
	end
	return at, args
end

local function pass(f, key, at, args, nargs)
	local code = f.code
	frame.address(f, insn.reg.R1, at)
	code:set(insn.reg.R2, #key + NUL)
	frame.move(f, frame.fetch(f, CTXREG, insn.reg.R3), insn.reg.R3)
	if nargs == 0 then
		code:set(insn.reg.R4, 0) -- the verifier takes a null pointer where the size is zero
	else
		frame.address(f, insn.reg.R4, args)
	end
	code:set(insn.reg.R5, nargs * frame.SLOT)
end

function runtime.call(f, pc, ins, state, callee)
	if callee.t ~= RUN then
		frame.refuse(f, pc, "a runtime is called through its method; write %s", written(callee))
	end
	placed(f, pc, state, callee)
	local code, key, nargs = f.code, callee.k.key, arguments(f, pc, ins, state)
	local at, args = stage(f, pc, ins, state, key, nargs)
	pass(f, key, at, args, nargs)
	code:kfunc(f.unit.kfunc)
	insert(f.calls, {line = f.proto.lines[pc], key = key})
	if ins.c > 1 then
		frame.extend(f, insn.reg.R0, INTSIZE)
		frame.setreg(f, ins.a, insn.reg.R0)
		state[ins.a] = {t = ANSWER, name = callee.name}
	end
end

-- whether a register holds what a call answered, alone or joined with another type
function runtime.answers(value)
	return value ~= nil and (value.t & ANSWER) ~= 0
end

-- the answer the arm that found one holds, a number from here on
local function number(_, _, state, i, value)
	state[i] = {t = frame.INT, name = value.name}
end

-- 'if v then' and 'v == nil' compare the answer with the kfunc's -1; taken is whether the opcode's
-- jump is the arm that found a number
function runtime.test(f, pc, ins, state, taken)
	local value = state[ins.a]
	if value.t ~= ANSWER then
		frame.refuse(f, pc, "%s joined another value here, whose nil is 0 and not -1; test it before the paths join",
			frame.named(value, "a runtime answer"))
	end
	return frame.narrow(f, pc, ins, state, ABSENT, taken, number)
end

return runtime

