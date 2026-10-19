--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the forconst case (see forconst.sh).

local corpus = require("tests.luaebpf.corpus")

local makers = {}

function makers.forward() return function(_) local s = 0 for i = 1, 5 do s = s + i end return s end end
---@diagnostic disable-next-line: count-down-loop
function makers.zerotrip() return function(_) local s = 7 for i = 1, 0 do s = s + i end return s end end
function makers.descending() return function(_) local s = 0 for i = 10, 1, -2 do s = s + i end return s end end
function makers.bigstep() return function(_) local s = 0 for i = 0, 10, 3 do s = s + i end return s end end
function makers.onestep() return function(_) local s = 0 for i = -3, 3 do s = s + i end return s end end
function makers.nested()
	return function(_)
		local s = 0
		for i = 1, 3 do
			for j = 1, 4 do
				s = s + i * j
			end
		end
		return s
	end
end

local order = {"forward", "zerotrip", "descending", "bigstep", "onestep", "nested"}

local rows = corpus.new()
for _, op in ipairs(order) do
	rows:declare(op, makers[op]())
end
rows:close()

