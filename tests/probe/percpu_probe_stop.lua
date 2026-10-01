--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, stop in a percpu runtime (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local test   = require("util").test

local function nop() end

test("stop, enable and disable are refused in a percpu runtime", function()
	local p = probe.new(systab["personality"], {pre = nop})
	for _, method in ipairs({"stop", "enable", "disable"}) do
		local ok, err = pcall(p[method], p)
		assert(not ok, method .. " was accepted")
		assert(err:match("percpu object owns this probe"), method .. " raised something else: " .. tostring(err))
	end
end)

