-- see the cases under tests/luaebpf: a program file's body declares its rows through here, and
-- writes beside the object what the interpreter answered for each, which the case compares
-- against what the compiled program returns.

local class = require("class")
local xdp   = require("bpf.xdp")

local corpus = {}

local rows = class{}

local function answer(ok, value)
	if not ok then
		return "raises"
	end
	if type(value) == "boolean" then
		return value and "1" or "0"
	end
	return tostring(value & 0xffffffff)
end

function corpus.new(path)
	return rows:new{out = assert(io.open(path or "oracle.txt", "w"))}
end

function rows:declare(name, fn, opts)
	opts = opts or {}
	opts.name = name
	xdp.program(fn, opts)
	self.out:write(name, "\t", answer(pcall(fn, 0)), "\n")
end

function rows:close()
	self.out:close()
end

return corpus

