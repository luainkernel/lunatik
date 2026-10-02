--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier lock test (see lock.sh).

local lunatik = require("lunatik")

local HOLDER <const> = "tests/notifier/lock_holder"

local holder <close> = lunatik.runtime(HOLDER)
holder:resume()

