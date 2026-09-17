-- see divzero.sh
local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp")

local MIN <const> = math.mininteger

local makers = {}

function makers.idivzero(a) return function(ctx) return a // 0 end end
function makers.modzero(a) return function(ctx) return a % 0 end end
function makers.idivminus(a) return function(ctx) return a // -1 end end
function makers.modminus(a) return function(ctx) return a % -1 end end
function makers.idivreg(a) return function(ctx) local d = a - a return 100 // d end end
function makers.modreg(a) return function(ctx) local d = a - a return 100 % d end end

local order = {"idivzero", "modzero", "idivminus", "modminus", "idivreg", "modreg"}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, a in ipairs({7, -7, MIN, 0}) do
		rows:declare(op .. i, makers[op](a), {default = action.REDIRECT})
	end
end
rows:close()

