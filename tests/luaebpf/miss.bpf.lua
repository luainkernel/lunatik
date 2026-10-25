--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the miss case (see miss.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local lua       = xdp.runtime("tests/luaebpf/miss")
local inprocess = xdp.runtime("tests/luaebpf/inprocess")

-- PASS is the callback's verdict and DROP the program's own where the call answered nil
local function miss(_)
	local verdict = lua()
	if verdict then
		return verdict
	end
	return action.DROP
end

local function process(_)
	local verdict = inprocess()
	if verdict then
		return verdict
	end
	return action.DROP
end

-- the nil arm returns the answer, which a program returns as its default verdict
local function returned(_)
	local verdict = lua()
	if verdict then
		return action.PASS
	end
	return verdict
end

-- the nil arm leaves the answer joined with a boolean, whose test reads nil's word as false
local function joined(_)
	local verdict = lua()
	if verdict then
		verdict = true
	end
	if verdict then
		return action.PASS
	end
	return action.DROP
end

-- the three other tests of the answer, each DROP on its nil arm and the verdict on its number arm
local function negated(_)
	local verdict = lua()
	if not verdict then
		return action.DROP
	end
	return verdict
end

local function unequal(_)
	local verdict = lua()
	if verdict ~= nil then
		return verdict
	end
	return action.DROP
end

local function equal(_)
	local verdict = lua()
	if verdict == nil then
		return action.DROP
	end
	return verdict
end

xdp.program(miss, {name = "miss"})
xdp.program(process, {name = "process"})
xdp.program(returned, {name = "returned", default = action.TX})
xdp.program(joined, {name = "joined"})
xdp.program(negated, {name = "negated"})
xdp.program(unequal, {name = "unequal"})
xdp.program(equal, {name = "equal"})

