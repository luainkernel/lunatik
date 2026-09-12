--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, stop in a percpu runtime (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local test   = require("util").test

local function nop() end

test("stop and enable are refused in a percpu runtime", function()
	local p = probe.new(systab["personality"], {pre = nop})
	local ok, err = pcall(p.stop, p)
	assert(not ok, "stop was accepted")
	assert(err:match("percpu object owns this probe"), "stop raised something else: " .. tostring(err))
	local okenable, errenable = pcall(p.enable, p, false)
	assert(not okenable, "enable was accepted")
	assert(errenable:match("percpu object owns this probe"), "enable raised something else: " .. tostring(errenable))
end)

