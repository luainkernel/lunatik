--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the callback case (see callback.sh).

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action

local MAGIC <const> = 0x5555000000004c41 -- whose low 32 bits are not MAGIC
local WRONG <const> = 0x5555000000004c42 -- MAGIC with one byte changed

local words = lunatik.runtime("tests/luaebpf/words")

-- TX where the call answered nil, a verdict the callback never returns
local function answer(_)
	local verdict = words:run(MAGIC)
	if verdict then
		return verdict
	end
	return action.TX
end

local function noargs(_)
	local verdict = words:run()
	if verdict then
		return verdict
	end
	return action.TX
end

local function wrong(_)
	local verdict = words:run(WRONG)
	if verdict then
		return verdict
	end
	return action.TX
end

local function pair(_)
	local verdict = words:run(WRONG, MAGIC)
	if verdict then
		return verdict
	end
	return action.TX
end

xdp.program(answer, {name = "answer"})
xdp.program(noargs, {name = "noargs"})
xdp.program(wrong, {name = "wrong"})
xdp.program(pair, {name = "pair"})

