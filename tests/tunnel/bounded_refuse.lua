--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side refusal script for the bounded send test (see bounded.sh).

local pair   = require("tests.tunnel.pair")
local tunnel = require("tunnel")

-- the sockets are never connected, since the refusal comes before tunnel.body
-- touches either of them
local function refuses(option, value)
	local a, b = pair.tcp(), pair.tcp()
	local refusal = "tunnel: " .. option .. " must be positive"
	local ok, err = pcall(tunnel.body, a, b, {[option] = value})
	assert(not ok, "tunnel.body took a " .. option .. " of " .. value)
	assert(err:find(refusal, 1, true), "expected '" .. refusal .. "', got " .. tostring(err))
end

refuses("timeout", 0)
refuses("timeout", -1)
refuses("size", 0)
refuses("size", -1)
print("tunnel bounded: an option that is not positive is refused")

