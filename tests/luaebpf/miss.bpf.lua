-- see miss.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

-- the runtime inprocess.lua registers, which is started with no execution context
local INPROCESS <const> = "tests/luaebpf/inprocess"

local lua       = xdp.runtime()
local inprocess = xdp.runtime(INPROCESS)

-- DROP is the branch no runtime leads to and PASS is the callback's own verdict, so one program
-- over one packet tells the two apart with the runtime as the only variable
local function miss(ctx)
	local verdict = lua(0)
	if verdict then
		return verdict
	end
	return action.DROP
end

-- the nil branch returns the answer itself: a nil a compiled function reads is the emitter's own
-- zero word, never the -1 the kfunc handed back
local function nilword(ctx)
	local verdict = lua(0)
	if verdict then
		return action.PASS
	end
	return verdict
end

local function process(ctx)
	local verdict = inprocess(0)
	if verdict then
		return verdict
	end
	return action.DROP
end

xdp.program(miss, {name = "miss"})
xdp.program(nilword, {name = "nilword"})
xdp.program(process, {name = "process"})

