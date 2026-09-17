-- see arith.sh
local corpus = require("tests.luaebpf.corpus")

local MIN <const> = math.mininteger
local MAX <const> = math.maxinteger

local makers = {}

function makers.add(a, b) return function(ctx) return a + b end end
function makers.sub(a, b) return function(ctx) return a - b end end
function makers.mul(a, b) return function(ctx) return a * b end end
function makers.idiv(a, b) return function(ctx) return a // b end end
function makers.mod(a, b) return function(ctx) return a % b end end
function makers.band(a, b) return function(ctx) return a & b end end
function makers.bor(a, b) return function(ctx) return a | b end end
function makers.bxor(a, b) return function(ctx) return a ~ b end end
function makers.shl(a, b) return function(ctx) return a << b end end
function makers.shr(a, b) return function(ctx) return a >> b end end
function makers.unm(a, b) return function(ctx) return -a end end
function makers.bnot(a, b) return function(ctx) return ~a end end
-- the K forms, where Lua folds one operand into the constant table
function makers.addk(a, b) return function(ctx) return a + 1000000 end end
function makers.modk(a, b) return function(ctx) return a % 1000000 end end
function makers.idivk(a, b) return function(ctx) return a // 1000000 end end
function makers.bandk(a, b) return function(ctx) return a & 0xff00ff00ff end end
-- the immediate forms: ADDI, SHRI with a negated count, and SHLI, whose constant is on the left
function makers.addi(a, b) return function(ctx) return a + 3 end end
function makers.shri(a, b) return function(ctx) return a >> 4 end end
function makers.shli(a, b) return function(ctx) return a << 4 end end
function makers.shlconst(a, b) return function(ctx) return 3 << b end end

local order = {"add", "sub", "mul", "idiv", "mod", "band", "bor", "bxor", "shl", "shr", "unm",
	"bnot", "addk", "modk", "idivk", "bandk", "addi", "shri", "shli", "shlconst"}
local operands = {
	{7, 3}, {-7, 3}, {7, -3}, {-7, -3}, {0, 5}, {5, 0}, {MIN, -1}, {MIN, 1}, {-1, 63},
	{1, 64}, {1, 65}, {1, -1}, {255, 0}, {-1, MIN}, {MAX, 2}, {MIN, MAX},
}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, pair in ipairs(operands) do
		rows:declare(op .. i, makers[op](pair[1], pair[2]))
	end
end
rows:close()

