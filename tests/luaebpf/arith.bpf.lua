--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the arith case (see arith.sh).

local corpus = require("tests.luaebpf.corpus")

local MIN <const> = math.mininteger
local MAX <const> = math.maxinteger

local makers = {}

function makers.add(a, b) return function(_) return a + b end end
function makers.sub(a, b) return function(_) return a - b end end
function makers.mul(a, b) return function(_) return a * b end end
function makers.idiv(a, b) return function(_) return a // b end end
function makers.mod(a, b) return function(_) return a % b end end
function makers.band(a, b) return function(_) return a & b end end
function makers.bor(a, b) return function(_) return a | b end end
function makers.bxor(a, b) return function(_) return a ~ b end end
function makers.shl(a, b) return function(_) return a << b end end
function makers.shr(a, b) return function(_) return a >> b end end
function makers.unm(a) return function(_) return -a end end
function makers.bnot(a) return function(_) return ~a end end
-- the K forms, where Lua folds one operand into the constant table
function makers.addk(a) return function(_) return a + 1000000 end end
function makers.modk(a) return function(_) return a % 1000000 end end
function makers.idivk(a) return function(_) return a // 1000000 end end
function makers.bandk(a) return function(_) return a & 0xff00ff00ff end end
-- the immediate forms: ADDI, SHRI with a negated count, and SHLI, whose constant is on the left
function makers.addi(a) return function(_) return a + 3 end end
function makers.shri(a) return function(_) return a >> 4 end end
function makers.shli(a) return function(_) return a << 4 end end
function makers.shlconst(_, b) return function(_) return 3 << b end end

local order = {"add", "sub", "mul", "idiv", "mod", "band", "bor", "bxor", "shl", "shr", "unm",
	"bnot", "addk", "modk", "idivk", "bandk", "addi", "shri", "shli", "shlconst"}
local operands = {
	{7, 3}, {-7, 3}, {7, -3}, {-7, -3}, {0, 5}, {5, 0}, {MIN, -1}, {MIN, 1}, {-1, 63},
	{1, 64}, {1, 65}, {1, -1}, {255, 0}, {-1, MIN}, {MAX, 2}, {MIN, MAX}, {7, MIN}, {MIN, MIN},
}

corpus.declare(makers, order, operands)

