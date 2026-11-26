--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action
local https   = require("examples.common.https")

local sni = lunatik.runtime("examples/filter/sni")

local function filter_https(ctx)
	local p = ctx:packet()
	local payload = https.payload(p)
	if payload == https.NONE then
		return action.PASS
	end
	return sni:run(payload) or action.PASS
end

return xdp.program(filter_https, {default = action.PASS})

