--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/require test (see run.sh).
--

local lunatik = require("lunatik")
local test    = require("util").test

local SCRIPT <const> = "tests/lua/require_armed"

local contexts <const> = {"softirq", "hardirq"}

for _, context in ipairs(contexts) do
	test("a " .. context .. " callback loads only what the script body loaded", function()
		local runtime <close> = lunatik.runtime(SCRIPT, context)
		runtime:resume()
	end)
end

