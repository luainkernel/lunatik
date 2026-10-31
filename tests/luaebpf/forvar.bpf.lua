--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the forvar case (see forvar.sh).

local corpus = require("tests.luaebpf.corpus")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local SCALE <const> = 200000001 -- 2,800,000,014 passes; odd, or the verifier walks the known low bits of the count

-- a 'for' whose step the callee gets at run time: the check reaches the default verdict through
-- the flag, as a division's does
local function sum(step)
	local s = 0
	for i = 1, 10, step do
		s = s + i
	end
	return s
end

local makers = {}

-- an upvalue is a value the compiler holds, so the bound is made a program value by arithmetic
function makers.varlimit(n) return function(_) local s = 0 for i = 1, n + 1 do s = s + i end return s end end
function makers.varstep(n) return function(_) local s = 0 for i = 1, 20, n + 1 do s = s + i end return s end end
function makers.varinit(n) return function(_) local s = 0 for i = n + 1, 6 do s = s + i end return s end end
function makers.calledstep(n) return function(_) local v = sum(n) return v end end

local order = {"varlimit", "varstep", "varinit", "calledstep"}
local operands = {{0}, {4}, {-1}, {-6}}

corpus.declare(makers, order, operands, action.REDIRECT)

-- a bound the verifier cannot hold, past any budget the kernel gives may_goto; no oracle row, which
-- would make every pass
local function spent(ctx)
	local p = ctx:packet()
	local s = 0
	for _ = 1, #p * SCALE do
		s = s + 1
	end
	return s
end

-- the same loop in a called function, whose spent budget reaches the caller through the flag
local function spin(p)
	local s = 0
	for _ = 1, #p * SCALE do
		s = s + 1
	end
	return s
end

local function calledspent(ctx)
	local p = ctx:packet()
	local v = spin(p)
	return v
end

xdp.program(spent, {name = "spent", default = action.REDIRECT})
xdp.program(calledspent, {name = "calledspent", default = action.REDIRECT})

