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

-- two calls in a loop whose bound the program computes: each writes the name and the argument below
-- the frame, under the loop's iterator, which the verifier refuses to step once overwritten; the bound
-- is the runtime's answer: the context's layout comes from the host's BTF, refused for the other byte order
local function looped(_)
	local n = words:run()
	if not n then
		return action.TX
	end
	local verdict = action.TX
	for _ = n, n + 1 do
		local v = words:run(MAGIC)
		if v then
			verdict = v
		end
	end
	return verdict
end

xdp.program(answer, {name = "answer", default = action.PASS})
xdp.program(noargs, {name = "noargs", default = action.PASS})
xdp.program(wrong, {name = "wrong", default = action.PASS})
xdp.program(pair, {name = "pair", default = action.PASS})
xdp.program(looped, {name = "looped", default = action.PASS})

