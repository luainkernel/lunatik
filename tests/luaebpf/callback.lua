--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the escape hatch test (see callback.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local MAGIC <const> = 0x5555000000004c41 -- matches callback.bpf.lua

local function test_callback(ctx)
	local argument = ctx:argument()
	if #argument == 0 then
		ctx:action(action.PASS)
	elseif argument:getint64(0) == MAGIC then
		ctx:action(action.DROP)
	else
		ctx:action(action.ABORTED)
	end
end

xdp.attach(test_callback)

