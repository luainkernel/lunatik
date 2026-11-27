--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the callback case calling one runtime from two program types (see callback.sh).

local xdp     = require("bpf.xdp")
local tc      = require("bpf.tc")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action
local tcact   = require("linux.tc").action

local words = lunatik.runtime("tests/luaebpf/words")

local function ingress(_)
	local verdict = words:run(1)
	if verdict then
		return verdict
	end
	return 2
end

local function classify(_)
	local verdict = words:run(1)
	if verdict then
		return verdict
	end
	return 0
end

xdp.program(ingress, {name = "ingress", default = action.PASS})
tc.program(classify, {name = "classify", default = tcact.OK})

