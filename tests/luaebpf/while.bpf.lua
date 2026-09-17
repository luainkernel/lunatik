-- see while.sh
local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp")

local NEVER   <const> = -100 -- a limit no row carries, so the test folds and the loop is never run
local BASE    <const> = 100  -- and a verdict that cannot be the default either
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

-- a while whose limit the program computes, since an upvalue is a value the compiler holds and
-- arithmetic on it is not
local makers = {}

function makers.whilelimit(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + 1 do
			s = s + i
			i = i + 1
		end
		return s
	end
end

function makers.repeatuntil(n)
	return function(ctx)
		local s, i = 0, 1
		repeat
			s = s + i
			i = i + 1
		until i > n + 1
		return s
	end
end

function makers.broken(n)
	return function(ctx)
		local s, i = 0, 1
		while true do
			s = s + i
			i = i + 1
			if i > n + 1 then
				break
			end
		end
		return s
	end
end

function makers.nested(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + 1 do
			local j = 1
			while j <= i do
				s = s + j
				j = j + 1
			end
			i = i + 1
		end
		return s
	end
end

-- a condition the compiler settles: the loop is never entered, and its back edge never emitted
function makers.folded(n)
	return function(ctx)
		local s = 0
		while n == NEVER do
			s = s + 1
		end
		return s + n + BASE
	end
end

-- a limit the verifier cannot know either: what the context carries is an unknown word to it, so
-- the loop is bounded by the header and by nothing else, which is the row the drop hook needs
local function contextlimit(ctx)
	local s, i = 0, 1
	while i <= ctx.ingress_ifindex do
		s = s + i
		i = i + 1
	end
	return s
end

local order = {"whilelimit", "repeatuntil", "broken", "nested", "folded"}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, n in ipairs({0, 4, -1, -6}) do
		rows:declare(op .. i, makers[op](n), {default = action.REDIRECT})
	end
end
rows:declare("ctxlimit", contextlimit, {default = action.REDIRECT},
	corpus.context("ctxlimit", "xdp_md", {ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME))
rows:close()

