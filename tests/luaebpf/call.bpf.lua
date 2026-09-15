-- see call.sh
local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp")

local function twice(x)
	return x + x
end

local function quadruple(x)
	local doubled = twice(x)
	local result = twice(doubled)
	return result
end

local function four(a, b, c, d)
	return a + b + c + d
end

local function half(n, d)
	return n // d
end

-- every path through this one raises, so its abort tail is the only exit the call reaches
local function always(n)
	local zero = n - n
	return 1 // zero
end

-- the deepest chain MAX_CALL_FRAMES takes: the program's own frame and seven more, each able to
-- abort, so the flag is forwarded one frame at a time
local function deep7(x) return 100 // x end
local function deep6(x) local v = deep7(x) return v // 1 end
local function deep5(x) local v = deep6(x) return v // 1 end
local function deep4(x) local v = deep5(x) return v // 1 end
local function deep3(x) local v = deep4(x) return v // 1 end
local function deep2(x) local v = deep3(x) return v // 1 end
local function deep1(x) local v = deep2(x) return v // 1 end

local makers = {}

function makers.once(n) return function(ctx) local v = twice(n) return v end end
function makers.twolevels(n) return function(ctx) local v = quadruple(n) return v end end
function makers.fourarguments(n) return function(ctx) local v = four(n, 1, 2, 3) return v end end
function makers.shared(n) return function(ctx) local v = twice(n) + quadruple(n) return v end end
function makers.deepest(n) return function(ctx) local v = deep1(n) return v end end
function makers.calleddiv(n) return function(ctx) local v = half(10, n) return v end end
function makers.onlyabort(n) return function(ctx) local v = always(n) return v end end
-- a call asking for two results, where Lua fills the second with nil
function makers.oneresult(n) return function(ctx) local v, w = twice(n) if w == nil then return 11 end return v end end
-- more live values than the emitter keeps in registers, so the rest go to the frame
function makers.spilled(n)
	return function(ctx)
		local a, b, c, d = 1, 2, 3, 4
		local e, f, g, h = 5, 6, 7, 8
		local i, j, k, l = 9, 10, 11, 12
		local sum = a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8
		local rest = i * 9 + j * 10 + k * 11 + l * 12
		local through = twice(sum)
		return through + rest + n
	end
end

local order = {"once", "twolevels", "fourarguments", "shared", "deepest", "calleddiv", "onlyabort",
	"oneresult", "spilled"}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, n in ipairs({0, 3, -5, 1000000}) do
		rows:declare(op .. i, makers[op](n))
	end
end
-- the same raise under the other default, so the answer is the verdict the file asked for
for i, n in ipairs({0, 3}) do
	rows:declare("dropdiv" .. i, makers.calleddiv(n), {default = action.DROP})
end
rows:close()

