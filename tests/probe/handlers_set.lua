--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, a set whose runtimes disagree (see handlers.sh).

local lunatik = require("lunatik")
local probe   = require("probe")
local systab  = require("syscall.table")
local prints  = require("tests.probe.prints")

local handlers = {pre = prints.pre}

if lunatik.cpu() > 0 then
	handlers.post = prints.post
end

probe.new(systab["personality"], handlers)

