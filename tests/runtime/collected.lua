--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the collected test (see collected.sh).

local lunatik = require("lunatik")

local CHILD <const> = "tests/runtime/collected_child"

lunatik.runtime(CHILD)
lunatik.percpu(CHILD)
collectgarbage()

