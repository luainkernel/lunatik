-- see forvar.sh
local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp")

local makers = {}

-- an upvalue is a value the compiler holds, so the bound is made a program value by arithmetic
function makers.varlimit(n) return function(ctx) local s = 0 for i = 1, n + 1 do s = s + i end return s end end
function makers.varstep(n) return function(ctx) local s = 0 for i = 1, 20, n + 1 do s = s + i end return s end end
function makers.varinit(n) return function(ctx) local s = 0 for i = n + 1, 6 do s = s + i end return s end end

local order = {"varlimit", "varstep", "varinit"}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, n in ipairs({0, 4, -1, -6}) do
		rows:declare(op .. i, makers[op](n), {default = action.REDIRECT})
	end
end
rows:close()

