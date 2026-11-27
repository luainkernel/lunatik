--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the report case (see report.sh).

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action
local first  = lunatik.runtime("tests/luaebpf/first")
local second = lunatik.runtime("tests/luaebpf/second")

-- two calls in one program
local function both(_)
	local a = first:run(1)
	if a then
		return a
	end
	local b = second:run(2)
	if b then
		return b
	end
	return 0
end

local function one(_)
	local c = second:run(3)
	if c then
		return c
	end
	return 0
end

xdp.program(both, {name = "both", default = action.PASS})
xdp.program(one, {name = "one", default = action.PASS})

