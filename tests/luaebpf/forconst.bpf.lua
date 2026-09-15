-- see forconst.sh
local corpus = require("tests.luaebpf.corpus")

local makers = {}

function makers.forward(n) return function(ctx) local s = 0 for i = 1, 5 do s = s + i end return s end end
function makers.zerotrip(n) return function(ctx) local s = 7 for i = 1, 0 do s = s + i end return s end end
function makers.descending(n) return function(ctx) local s = 0 for i = 10, 1, -2 do s = s + i end return s end end
function makers.bigstep(n) return function(ctx) local s = 0 for i = 0, 10, 3 do s = s + i end return s end end
function makers.onestep(n) return function(ctx) local s = 0 for i = -3, 3 do s = s + i end return s end end
function makers.nested(n)
	return function(ctx)
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
	rows:declare(op, makers[op](0))
end
rows:close()

