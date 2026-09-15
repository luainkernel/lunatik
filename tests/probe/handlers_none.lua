--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, an empty handlers table (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")

probe.new(systab["personality"], {})

