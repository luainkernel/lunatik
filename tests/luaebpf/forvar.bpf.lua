--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the forvar case (see forvar.sh).

local corpus = require("tests.luaebpf.corpus")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local SCALE <const> = 200000001 -- 2,800,000,014 passes; odd, or the verifier walks the known low bits of the count
local LOOPS <const> = 1 << 23   -- the passes after the first the kernel's iterator counts, BPF_MAX_LOOPS
local WIDE  <const> = 1 << 32   -- a count whose low 32 bits, the int the iterator takes, are 0
local TURNS <const> = 64        -- times LOOPS: seconds of passes, past the time and the passes may_goto gives a call

-- a 'for' whose step the callee gets at run time: the check stops the program through the flag, as
-- a division's does
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
-- a callee that stops answers 0, XDP_ABORTED's value, so the row adds one past the call
function makers.calledstep(n) return function(_) local v = sum(n) return v + 1 end end

-- each way out of a loop the compiler cannot bound, alone and from an inner one, which destroys the
-- iterator of every loop it leaves, or the verifier refuses the program; a goto to the step is none
function makers.breaks(n)
	return function(_) local s = 0 for i = 1, n + 10 do if i == n + 4 then break end s = s + i end return s end
end
function makers.returns(n)
	return function(_)
		local s = 0 for i = 1, n + 10 do if i == n + 4 then return s * 100 + i end s = s + i end return s
	end
end
function makers.divides(n) return function(_) local s = 0 for i = n + 1, 3 do s = s + 12 // i end return s end end
function makers.continues(n)
	return function(_)
		local s = 0 for i = 1, n + 6 do if i % 2 == 0 then goto continue end s = s + i ::continue:: end return s
	end
end
function makers.nested(n)
	return function(_)
		local s = 0 for i = 1, n + 3 do for j = 1, n + 4 do if j > i then break end s = s + j end end return s
	end
end
function makers.escapes(n)
	return function(_)
		local s = 0
		for i = 1, n + 5 do for j = 1, n + 5 do if i * j == 6 then goto out end s = s + 1 end end
		::out::
		return s
	end
end
function makers.innerreturn(n)
	return function(_)
		local s = 0
		for i = 1, n + 3 do for j = 1, n + 3 do if i + j == 5 then return s * 10 + i end s = s + 1 end end
		return s
	end
end
function makers.innerdivides(n)
	return function(_)
		local s = 0 for i = 1, n + 3 do for j = 1, n + 3 do s = s + 6 // (i + j - 4) end end return s
	end
end
function makers.calledinside(n)
	return function(_) local s = 0 for i = 1, n + 3 do s = s + sum(i + n) end return s end
end

local order = {"varlimit", "varstep", "varinit", "calledstep", "breaks", "returns", "divides", "continues",
	"nested", "escapes", "innerreturn", "innerdivides", "calledinside"}
local operands = {{0}, {4}, {-1}, {-6}}

-- a bound the verifier cannot hold, of more passes than the iterator's int counts; no oracle row, which
-- would make every pass
local function spent(keep)
	return function(ctx)
		local p = ctx:packet()
		local s = 0
		for _ = 1, #p * SCALE do
			s = s + 1
		end
		keep(s)
	end
end

-- the same loop in a called function, whose stop reaches the caller through the flag
local function spin(p)
	local s = 0
	for _ = 1, #p * SCALE do
		s = s + 1
	end
	return s
end

local function calledspent(keep)
	return function(ctx)
		local p = ctx:packet()
		local v = spin(p)
		keep(v)
	end
end

-- a count the iterator's int cannot hold, whose low 32 bits would make one pass; no oracle row, which
-- would make every pass
local function wide(keep)
	return function(ctx)
		local p = ctx:packet()
		local s = 0
		for _ = #p, #p + WIDE do
			s = s + 1
		end
		keep(s)
	end
end

-- one pass more than the kernel's iterator counts, past which it counts none
local function past(keep)
	return function(ctx)
		local p = ctx:packet()
		local s = 0
		for _ = #p, #p + LOOPS + 1 do
			s = s + 1
		end
		keep(s)
	end
end

-- two loops the iterator counts whole, whose passes together outrun what the kernel gives the may_goto
-- of one call, counted or timed; no oracle row, which would make every pass
local function drained(keep)
	return function(ctx)
		local p = ctx:packet()
		local s = 0
		for _ = #p, #p + TURNS do
			for _ = #p, #p + LOOPS do
				s = s + 1
			end
		end
		keep(s)
	end
end

-- before corpus.declare, whose close sizes the map `results` by the programs declared so far
corpus.program(xdp.program, {name = "spent", default = action.REDIRECT}, spent)
corpus.program(xdp.program, {name = "calledspent", default = action.REDIRECT}, calledspent)
corpus.program(xdp.program, {name = "wide", default = action.REDIRECT}, wide)
corpus.program(xdp.program, {name = "past", default = action.REDIRECT}, past)
corpus.program(xdp.program, {name = "drained", default = action.REDIRECT}, drained)

corpus.declare(makers, order, operands, action.REDIRECT)

