--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp").action
local packet = require("tests.xdp.packet")

local held = setmetatable({}, {__mode = "v"})

local function drop_then_detach(ctx)
	if not packet.isping(ctx:packet()) then
		return action.PASS
	end
	xdp.detach()
	held.ctx = ctx
	ctx = nil
	collectgarbage()
	if held.ctx == nil then
		print("xdp detach test fail: the context was collected inside its callback")
	else
		print("xdp detach test pass: verdict returned and callback detached")
	end
	return action.DROP
end

xdp.attach(drop_then_detach)

