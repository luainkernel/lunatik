--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/require test (see run.sh).
--

local lunatik = require("lunatik")
local test    = require("tests.lib").test

local SCRIPT <const> = "tests/lua/require_armed"
local STRAY <const> = "/lib/modules/lua/tests/lua/?.lua" -- holds device.lua

local contexts <const> = {"softirq", "hardirq"}

for _, context in ipairs(contexts) do
	test("a " .. context .. " callback requires no binding or Lua file the body did not load", function()
		local runtime <close> = lunatik.runtime(SCRIPT, context)
		runtime:resume()
	end)
end

test("a binding is found before a Lua file of its name", function()
	local path = package.path
	package.path = STRAY
	local ok, device = pcall(require, "device")
	package.path = path
	assert(ok, device)
	assert(type(device.new) == "function", "device is not the binding")
end)

