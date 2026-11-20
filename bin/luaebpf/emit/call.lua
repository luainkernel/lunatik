--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The returns, CALL and the invocation of a subprogram: a call is a method of a proxy, a call into the
-- kernel Lua runtime, or a BPF-to-BPF call to a Lua function the file declares, whose abort comes back
-- through a flag in the caller's frame.
-- @module luaebpf.emit.call

local insn    = require("luaebpf.insn")
local frame   = require("luaebpf.emit.frame")
local loads   = require("luaebpf.emit.loads")
local packet  = require("luaebpf.emit.packet")
local runtime = require("luaebpf.emit.runtime")

local ABORTED <const> = frame.ABORTED
local BOOL    <const> = frame.BOOL
local INT     <const> = frame.INT
local METHOD  <const> = loads.METHOD
local NIL     <const> = frame.NIL
local PACKET  <const> = packet.PACKET

local MAXARGS <const> = 4 -- MAX_BPF_FUNC_REG_ARGS, less the register the abort pointer takes

local call = {}

-- whether the compiler holds a verdict that is none of its program type's actions
local function isoutside(actions, value)
	local k = value.k
	return frame.isinteger(value) and k ~= nil and (k < actions.first or k > actions.last)
end

-- a verdict is one of its program type's actions, which no bits of nil or of a boolean are
local function checkverdict(f, pc, value)
	if value.t & NIL ~= 0 then -- a register carries nil and 0 as one word
		frame.refuse(f, pc, "the verdict may be nil here; test it first")
	end
	if value.t & BOOL ~= 0 then
		frame.refuse(f, pc, "the verdict may be a boolean here; return an action")
	end
	local actions = f.unit.actions
	if isoutside(actions, value) then
		frame.refuse(f, pc, "the verdict %d is not %s", value.k, actions.name)
	end
end

-- a verdict the program computes outside its type's actions stops the program, as luakfunc_action
-- answers one a kernel callback returns as it answers a callback that raised, logging what it logs
local function testverdict(f, pc, value)
	if value.k ~= nil or f.drop == "action" then -- checkverdict held one the compiler knows
		return
	end
	local actions, invalid = f.unit.actions, frame.stop(f, pc, "invalid action")
	f.code:branchi(insn.jump.JSLT, insn.reg.R0, actions.first, invalid)
	f.code:branchi(insn.jump.JSGT, insn.reg.R0, actions.last, invalid)
end

local function returnvalue(f, pc, state, i)
	local value = state[i]
	if f.isprogram then
		checkverdict(f, pc, value)
	end
	f.rettype = f.rettype | value.t
	if f.drop ~= "verdict" then
		f.code:alu(insn.alu.MOV, insn.reg.R0, frame.getreg(f, pc, state, i, insn.reg.R0))
		if f.isprogram then
			testverdict(f, pc, value)
		end
	end
end

local function returns(f, pc, state, i)
	frame.leave(f)
	if i == nil or state[i].t == NIL then -- the hook reads 'return' and 'return nil' alike
		f.rettype = f.rettype | NIL
		if f.drop ~= "verdict" then
			f.code:set(insn.reg.R0, f.isprogram and f.default or 0)
		end
	else
		returnvalue(f, pc, state, i)
	end
	f.code:exit()
	return false
end

function call.RETURN(f, pc, ins, state)
	if ins.b == 0 or ins.b > 2 then
		frame.refuse(f, pc, "a compiled function returns at most one value")
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
		frame.resolve(f, pc, state, i, nil)
	end
end

local function callable(f, pc, callee)
	if callee == nil or type(callee.k) ~= "function" then
		frame.refuse(f, pc, "a call through a value the compiler cannot resolve")
	end
	if debug.getinfo(callee.k, "S").what == "C" then
		frame.refuse(f, pc, "'%s' is not a Lua function this program file declares", callee.name or "?")
	end
end

local function parameters(f, pc, ins, state)
	local nargs = ins.b - 1
	if nargs > MAXARGS then
		frame.refuse(f, pc, "a compiled function takes at most %d arguments, not %d", MAXARGS, nargs)
	end
	local params = {}
	for i = 1, nargs do
		local value = state[ins.a + i]
		local kind = value ~= nil and value.t or 0
		if kind ~= INT and kind ~= PACKET then
			frame.refuse(f, pc, "argument #%d is a %s, and a compiled call passes numbers and packets",
				i, frame.typename(value))
		end
		params[i] = kind
	end
	return params
end

local function invoke(f, target, nargs)
	f.code:storei(insn.reg.FP, ABORTED, 0)
	frame.address(f, insn.reg.R1 + nargs, ABORTED)
	f.code:call(target.name)
	f.code:load(insn.reg.R1, insn.reg.FP, ABORTED)
	f.code:branchi(insn.jump.JNE, insn.reg.R1, 0, frame.abort(f))
end

local function subprogram(f, pc, ins, state, callee)
	callable(f, pc, callee)
	local params = parameters(f, pc, ins, state)
	local target = f.unit.subprogram(f, pc, callee.k, callee.name, params)
	for i = 1, #params do
		frame.move(f, frame.fetch(f, ins.a + i, insn.reg.R0 + i), insn.reg.R0 + i)
	end
	invoke(f, target, #params)
	if ins.c > 1 then
		frame.setreg(f, ins.a, insn.reg.R0)
		state[ins.a] = {t = target.rettype}
	end
end

function call.CALL(f, pc, ins, state)
	local callee = state[ins.a]
	if ins.b == 0 or ins.c == 0 then
		frame.refuse(f, pc, "a call with a variable number of values cannot be compiled")
	end
	if callee ~= nil and callee.t == METHOD then
		packet.method(f, pc, ins, state, callee)
	elseif callee ~= nil and runtime.isproxy(callee.k) then
		runtime.call(f, pc, ins, state, callee)
	else
		subprogram(f, pc, ins, state, callee)
	end
	filled(f, pc, ins, state)
end

return call

