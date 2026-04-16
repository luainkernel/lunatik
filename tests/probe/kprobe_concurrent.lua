--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kprobe_concurrent regression test (see kprobe_concurrent.sh).
--

local probe  = require("probe")
local systab = require("syscall.table")

local function handler() end

for _, address in pairs(systab) do
	probe.new(address, {pre = handler})
end

