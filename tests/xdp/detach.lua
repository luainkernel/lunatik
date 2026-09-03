--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")
local packet = require("tests.xdp.packet")

local function drop_then_detach(ctx)
	if not packet.isicmp(ctx:packet()) then
		ctx:action(action.PASS)
		return
	end
	ctx:action(action.DROP)
	xdp.detach()
	print("xdp detach test pass: verdict set and callback detached")
end

xdp.attach(drop_then_detach)

