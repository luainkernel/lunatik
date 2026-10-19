--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the divzero case (see divzero.sh).

local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp").action

local MIN <const> = math.mininteger

local makers = {}

function makers.idivzero(a) return function(_) return a // 0 end end
function makers.modzero(a) return function(_) return a % 0 end end
function makers.idivminus(a) return function(_) return a // -1 end end
function makers.modminus(a) return function(_) return a % -1 end end
function makers.idivreg(a) return function(_) local d = a - a return 100 // d end end
function makers.modreg(a) return function(_) local d = a - a return 100 % d end end

local order = {"idivzero", "modzero", "idivminus", "modminus", "idivreg", "modreg"}
local operands = {{7}, {-7}, {MIN}, {0}}

corpus.declare(makers, order, operands, action.REDIRECT)

