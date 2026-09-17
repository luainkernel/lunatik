-- see branch.sh
local corpus = require("tests.luaebpf.corpus")

local MIN <const> = math.mininteger
local MAX <const> = math.maxinteger
local TAG <const> = "branch"

local makers = {}

function makers.lt(a, b) return function(ctx) if a < b then return 11 end return 22 end end
function makers.le(a, b) return function(ctx) if a <= b then return 11 end return 22 end end
function makers.gt(a, b) return function(ctx) if a > b then return 11 end return 22 end end
function makers.ge(a, b) return function(ctx) if a >= b then return 11 end return 22 end end
function makers.eq(a, b) return function(ctx) if a == b then return 11 end return 22 end end
function makers.ne(a, b) return function(ctx) if a ~= b then return 11 end return 22 end end
-- the immediate forms, where the constant fits the opcode's signed operand
function makers.lti(a, b) return function(ctx) if a < 3 then return 11 end return 22 end end
function makers.lei(a, b) return function(ctx) if a <= -3 then return 11 end return 22 end end
function makers.gti(a, b) return function(ctx) if a > 3 then return 11 end return 22 end end
function makers.gei(a, b) return function(ctx) if a >= -3 then return 11 end return 22 end end
function makers.eqi(a, b) return function(ctx) if a == -1 then return 11 end return 22 end end
function makers.eqk(a, b) return function(ctx) if a == 1000000 then return 11 end return 22 end end
function makers.chain(a, b)
	return function(ctx)
		if a > 0 and b > 0 then
			return 11
		elseif a < 0 or b < 0 then
			return 33
		end
		return 22
	end
end
-- Lua's truth, which the bits do not carry: 0 is true, and only false and nil are not
function makers.zero(a, b) return function(ctx) if 0 then return 11 end return 22 end end
function makers.andzero(a, b) return function(ctx) local v = 0 and 1 return v end end
function makers.notnil(a, b) return function(ctx) local v = nil if not v then return 11 end return 22 end end
function makers.notfalse(a, b) return function(ctx) local v = false if not v then return 11 end return 22 end end
function makers.boolean(a, b) return function(ctx) return a < b end end
function makers.testset(a, b) return function(ctx) local v = (a > b) and a or b return v end end
function makers.orvalue(a, b) return function(ctx) local v = (a ~= 0) or (b ~= 0) return v end end
-- a value the compiler does not hold, against a constant only its type can answer for: the bits
-- carry neither nil, nor a boolean, nor a string apart from the zero every one of them shares
function makers.nilvalue(a, b) return function(ctx) local v = a + b if v == nil then return 11 end return 22 end end
function makers.truevalue(a, b) return function(ctx) local v = a < b if v == true then return 11 end return 22 end end
function makers.falsevalue(a, b) return function(ctx) local v = a < b if v == false then return 11 end return 22 end end
function makers.othervalue(a, b) return function(ctx) local v = a + b if v == TAG then return 11 end return 22 end end

local order = {"lt", "le", "gt", "ge", "eq", "ne", "lti", "lei", "gti", "gei", "eqi", "eqk",
	"chain", "zero", "andzero", "notnil", "notfalse", "boolean", "testset", "orvalue",
	"nilvalue", "truevalue", "falsevalue", "othervalue"}
local operands = {{1, 2}, {2, 1}, {-1, 1}, {1, -1}, {-2, -1}, {0, 0}, {MIN, MAX}, {MAX, MIN},
	{-1, 1000000}, {1000000, -1}}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, pair in ipairs(operands) do
		rows:declare(op .. i, makers[op](pair[1], pair[2]))
	end
end
rows:close()

