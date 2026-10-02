--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the runtime/cstack test (see cstack.sh): a runtime that creates itself.
--

local lunatik = require("lunatik")

local SELF <const> = "tests/runtime/cstack_self"

lunatik.runtime(SELF)

