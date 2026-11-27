--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the callback case with a function named as the kfunc (see callback.sh).

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action

local words = lunatik.runtime("tests/luaebpf/words")

local function bpf_luaxdp_run(n)
	return n + 1
end

return xdp.program(function(ctx)
	local queue = ctx:queue()
	local argument = bpf_luaxdp_run(queue)
	local verdict = words:run(argument)
	if verdict then
		return verdict
	end
	return 2
end, {name = "samename", default = action.PASS})

