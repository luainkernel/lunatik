--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The returns, CALL and the invocation of a subprogram: a call is a method of a proxy, or a BPF-to-BPF
-- call to a Lua function the file declares, whose abort comes back through a flag in the caller's frame.
-- @module luaebpf.emit.call

local insn   = require("luaebpf.insn")
local frame  = require("luaebpf.emit.frame")
local packet = require("luaebpf.emit.packet")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local getinfo = debug.getinfo
local abort, fetch, getreg, move, refuse = frame.abort, frame.fetch, frame.getreg, frame.move, frame.refuse
local resolve, setreg, typename = frame.resolve, frame.setreg, frame.typename
local method = packet.method

local ABORTED <const> = frame.ABORTED
local INT     <const> = frame.INT
local METHOD  <const> = frame.METHOD
local NIL     <const> = frame.NIL
local PACKET  <const> = frame.PACKET

local MAXARGS <const> = 4 -- MAX_BPF_FUNC_REG_ARGS, less the register the abort pointer takes

local call = {}

local function returns(f, pc, state, i)
	local dropped = f.drop == "verdict"
	if i == nil or state[i].t == NIL then -- the hook reads 'return' and 'return nil' alike
		f.rettype = f.rettype | NIL
		if not dropped then
			f.code:set(reg.R0, f.isprogram and f.default or 0)
		end
	else
		if f.isprogram and state[i].t & NIL ~= 0 then -- a register carries nil and 0 as one word
			refuse(f, pc, "the verdict may be nil here; test it first")
		end
		f.rettype = f.rettype | state[i].t
		if not dropped then
			f.code:alu(alu.MOV, reg.R0, getreg(f, pc, state, i, reg.R0))
		end
	end
	f.code:exit()
	return false
end

function call.RETURN(f, pc, ins, state)
	if ins.b == 0 or ins.b > 2 then
		refuse(f, pc, "a compiled function returns at most one value")
	end
	return returns(f, pc, state, ins.b == 2 and ins.a or nil)
end

function call.RETURN0(f, pc, _, state)
	return returns(f, pc, state, nil)
end

function call.RETURN1(f, pc, ins, state)
	return returns(f, pc, state, ins.a)
end

-- a compiled call answers with one value, so Lua fills every further result asked for with nil
local function filled(f, pc, ins, state)
	for i = ins.a + 1, ins.a + ins.c - 2 do
		resolve(f, pc, state, i, nil)
	end
end

local function callable(f, pc, callee)
	if callee == nil or type(callee.k) ~= "function" then
		refuse(f, pc, "a call through a value the compiler cannot resolve")
	end
	if getinfo(callee.k, "S").what == "C" then
		refuse(f, pc, "'%s' is not a Lua function this program file declares", callee.name or "?")
	end
end

local function parameters(f, pc, ins, state)
	local nargs = ins.b - 1
	if nargs > MAXARGS then
		refuse(f, pc, "a compiled function takes at most %d arguments, not %d", MAXARGS, nargs)
	end
	local params = {}
	for i = 1, nargs do
		local value = state[ins.a + i]
		local kind = value ~= nil and value.t or 0
		if kind ~= INT and kind ~= PACKET then
			refuse(f, pc, "argument #%d is a %s, and a compiled call passes numbers and packets",
				i, typename(value))
		end
		params[i] = kind
	end
	return params
end

local function invoke(f, target, nargs)
	f.code:storei(reg.FP, ABORTED, 0)
	f.code:alu(alu.MOV, reg.R1 + nargs, reg.FP)
	f.code:alui(alu.ADD, reg.R1 + nargs, ABORTED)
	f.code:call(target.name)
	f.code:load(reg.R1, reg.FP, ABORTED)
	f.code:branchi(jump.JNE, reg.R1, 0, abort(f))
end

function call.CALL(f, pc, ins, state)
	local callee = state[ins.a]
	if ins.b == 0 or ins.c == 0 then
		refuse(f, pc, "a call with a variable number of values cannot be compiled")
	end
	if callee ~= nil and callee.t == METHOD then
		method(f, pc, ins, state, callee)
		return filled(f, pc, ins, state)
	end
	callable(f, pc, callee)
	local params = parameters(f, pc, ins, state)
	local target = f.unit.subprogram(f, pc, callee.k, callee.name, params)
	for i = 1, #params do
		move(f, fetch(f, ins.a + i, reg.R0 + i), reg.R0 + i)
	end
	invoke(f, target, #params)
	if ins.c > 1 then
		setreg(f, ins.a, reg.R0)
		state[ins.a] = {t = target.rettype}
	end
	filled(f, pc, ins, state)
end

return call

