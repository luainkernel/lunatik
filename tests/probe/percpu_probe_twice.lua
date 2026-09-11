--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, duplicate registration (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local SYMBOL <const> = "sys_ni_syscall"

local function nop() end

probe.new(systab["personality"], {pre = nop})
probe.new(SYMBOL, {pre = nop}) -- a second kprobe in the same set, this one found by name

print("percpu probe twice: two targets armed")

probe.new(SYMBOL, {pre = nop})

