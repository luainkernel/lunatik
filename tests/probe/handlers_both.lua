--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, a table with both handlers (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local prints = require("tests.probe.prints")

probe.new(systab["personality"], {pre = prints.pre, post = prints.post})

