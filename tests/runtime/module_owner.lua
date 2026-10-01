--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the module_owner test (see module_owner.sh).

local lunatik = require("lunatik")
local set     = require("set")

local KEY <const> = "tests.runtime.module_owner"

lunatik._ENV[KEY] = set.new({"a"})

