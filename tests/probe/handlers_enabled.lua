--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, a probe disabled and enabled again on load (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local prints = require("tests.probe.prints")

local handle = probe.new(systab["personality"], {pre = prints.pre})
handle:disable()
handle:enable()

