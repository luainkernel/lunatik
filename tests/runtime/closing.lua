--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the closing test (see closing.sh).

local lunatik = require("lunatik")

local THREAD <const> = "tests/runtime/closing_thread"

lunatik.runtime(THREAD)
collectgarbage()

