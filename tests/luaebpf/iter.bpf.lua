-- see iter.sh
local corpus = require("tests.luaebpf.corpus")
local action = require("linux.xdp")

local BASE  <const> = 100 -- a verdict that cannot be the default, whatever the loop summed
local TIMES <const> = 10
local ZERO  <const> = 1   -- the iteration whose divisor is zero, where the interpreter raises

local makers = {}

function makers.whilelimit(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + 1 do
			s = s + i
			i = i + 1
		end
		return s + BASE
	end
end

function makers.repeatuntil(n)
	return function(ctx)
		local s, i = 0, 1
		repeat
			s = s + i
			i = i + 1
		until i > n + 1
		return s + BASE
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
		return s + BASE
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
		return s + BASE
	end
end

-- a return out of the loop body, which leaves the iterator behind unless the exit destroys it
function makers.returned(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + TIMES do
			s = s + i
			if s > n then
				return s + BASE
			end
			i = i + 1
		end
		return s
	end
end

-- a check that fails inside the loop takes the program's default verdict, which is a tail the
-- iterator has to be destroyed on the way to
function makers.aborted(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + 3 do
			s = s + TIMES // (i - ZERO)
			i = i + 1
		end
		return s + BASE
	end
end

-- a failed check inside each of two nested loops: the tail one takes destroys one iterator and
-- the tail the other takes destroys two, so the two tails cannot be the same one
function makers.nestedabort(n)
	return function(ctx)
		local s, i = 0, 1
		while i <= n + 3 do
			if i > TIMES then
				s = s + TIMES // (i - i)
			end
			local j = 1
			while j <= i do
				s = s + TIMES // (j - ZERO)
				j = j + 1
			end
			i = i + 1
		end
		return s + BASE
	end
end

-- a loop the program only reaches by a jump: nothing falls through into its head, so the
-- iterator has to be created where every edge into the loop lands and not below the jump before it
function makers.jumped(n)
	return function(ctx)
		local s, i = 0, 1
		if n > TIMES then
			s = BASE
		else
			while i <= n + 1 do
				s = s + i
				i = i + 1
			end
		end
		return s + BASE
	end
end

-- the same head reached both ways, by the jump the 'if' takes and by the fall-through below it
function makers.gated(n)
	return function(ctx)
		local s, i = 0, 1
		if n > TIMES then
			s = TIMES
		end
		while i <= n + 1 do
			s = s + i
			i = i + 1
		end
		return s + BASE
	end
end

-- a 'repeat' whose body opens with a loop of its own: Lua puts both back edges on one head, so
-- one iterator bounds the pair -- a second creation there would be reached by neither jump
function makers.sharedhead(n)
	return function(ctx)
		local s, i, k = 0, 1, TIMES
		repeat
			while i <= n + 1 do
				s = s + i
				i = i + 1
			end
			k = k - 1
		until k <= 0
		return s + BASE
	end
end

-- the numeric 'for' the compiler cannot bound takes the same lowering
function makers.counted(n)
	return function(ctx)
		local s = 0
		for i = 1, n + 1 do
			s = s + i
		end
		return s + BASE
	end
end

local order = {"whilelimit", "repeatuntil", "broken", "nested", "returned", "aborted",
	"nestedabort", "jumped", "gated", "sharedhead", "counted"}

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, n in ipairs({0, 4, -1, -6}) do
		rows:declare(op .. i, makers[op](n), {default = action.REDIRECT})
	end
end
rows:close()

