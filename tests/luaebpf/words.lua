--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel script of the callback case (see callback.sh).

local xdp    = require("xdp")
local action = require("linux.xdp").action

local MAGIC <const> = 0x5555000000004c41 -- MAGIC in callback.bpf.lua
local WRONG <const> = 0x5555000000004c42 -- WRONG in callback.bpf.lua
local WORD  <const> = 8

local function callback(ctx)
	local argument = ctx:argument()
	if #argument == 0 then
		return action.PASS
	end
	if #argument == WORD and argument:getint64(0) == MAGIC then
		return action.DROP
	end
	if #argument == 2 * WORD and argument:getint64(0) == WRONG and argument:getint64(WORD) == MAGIC then
		return action.DROP
	end
	return action.ABORTED
end

xdp.attach(callback)

