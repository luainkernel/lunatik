--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side relay for the transform test (see inspect.sh): plain.lua's relay
-- with an opts.transform that rewrites one direction and drops one payload.

local pair   = require("tests.tunnel.pair")
local tunnel = require("tunnel")

local upper = string.upper

local listener = pair.listener()
local a

-- the source socket is what tells the two directions apart, so A to B is
-- rewritten while B to A goes through untouched
local function inspect(data, from)
	if from ~= a then
		return data
	end
	if data == pair.dropped then
		return nil
	end
	return upper(data)
end

return function()
	local b
	a, b = pair.accept(listener)
	listener:close()
	if a == nil then
		return
	end
	tunnel.body(a, b, {transform = inspect})()
	print("tunnel inspect: relay ended")
end

