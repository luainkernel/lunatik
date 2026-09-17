-- see callback.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

-- the magic's low 32 bits are not the whole value, so a call that packed only four bytes would
-- reach the callback's rejection rather than its DROP; the wrong one differs from it in one byte
local MAGIC <const> = 0x5555000000004c41
local WRONG <const> = 0x5555000000004c42

-- the key lunatik run registers callback.lua under, which is what the default derives
local KEY <const> = "tests/luaebpf/callback"

local default = xdp.runtime()
local spelled = xdp.runtime(KEY)

-- TX where the kfunc answered -1, a verdict the callback never sets, so a row that reads it knows
-- no runtime was dispatched rather than that the callback refused the argument
local function answer(ctx)
	local verdict = default(MAGIC)
	if verdict then
		return verdict
	end
	return action.TX
end

local function named(ctx)
	local verdict = spelled(MAGIC)
	if verdict then
		return verdict
	end
	return action.TX
end

local function noargs(ctx)
	local verdict = default()
	if verdict then
		return verdict
	end
	return action.TX
end

local function wrong(ctx)
	local verdict = default(WRONG)
	if verdict then
		return verdict
	end
	return action.TX
end

xdp.program(answer, {name = "answer"})
xdp.program(named, {name = "named"})
xdp.program(noargs, {name = "noargs"})
xdp.program(wrong, {name = "wrong"})

