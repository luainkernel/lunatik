--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, the plain runtime methods (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local test   = require("util").test

local UNKNOWN <const> = "lunatik_no_such_symbol"

local function nop() end

test("a plain runtime stops its probe once and enables it while it lives", function()
	local p = probe.new(systab["personality"], {pre = nop})
	p:enable(false)
	p:enable(true)
	p:stop()
	p:stop() -- stopping again is a no-op
	local ok, err = pcall(p.enable, p, true)
	assert(not ok, "enable was accepted after stop")
	assert(err:match("null pointer"), "enable raised something else: " .. tostring(err))
end)

test("a probe on a symbol the kernel does not have is refused", function()
	local ok, err = pcall(probe.new, UNKNOWN, {pre = nop})
	assert(not ok, "a probe on an unknown symbol was accepted")
	assert(err:match("failed to register probe"), "probe.new raised something else: " .. tostring(err))
end)

