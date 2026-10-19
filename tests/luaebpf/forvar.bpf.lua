--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the forvar case (see forvar.sh).

local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp").action

local makers = {}

-- an upvalue is a value the compiler holds, so the bound is made a program value by arithmetic
function makers.varlimit(n) return function(_) local s = 0 for i = 1, n + 1 do s = s + i end return s end end
function makers.varstep(n) return function(_) local s = 0 for i = 1, 20, n + 1 do s = s + i end return s end end
function makers.varinit(n) return function(_) local s = 0 for i = n + 1, 6 do s = s + i end return s end end

local order = {"varlimit", "varstep", "varinit"}
local operands = {{0}, {4}, {-1}, {-6}}

corpus.declare(makers, order, operands, action.REDIRECT)

