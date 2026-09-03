--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp percpu dispatch test (see test_xdp.sh).

local lunatik = require("lunatik")
local xdp     = require("xdp")
local action  = require("linux.xdp")
local packet  = require("tests.xdp.packet")

local cpu = lunatik.cpu()

local function test_percpu(ctx)
	if packet.isicmp(ctx:packet()) then
		print("xdp percpu test hit: cpu " .. cpu)
	end
	ctx:action(action.PASS)
end

xdp.attach(test_percpu)

