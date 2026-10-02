--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Cases described in tests/signal/run.sh (signal/softirq).

local lunatik = require("lunatik")

local RECEIVER <const> = "tests/signal/softirq_recv"

local runtime <close> = lunatik.runtime(RECEIVER, "softirq")
runtime:resume()

