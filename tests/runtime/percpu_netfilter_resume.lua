--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the percpu netfilter test, registration from a resumed body (see percpu_netfilter.sh).

local lunatik = require("lunatik")

local RESUMED <const> = "tests/runtime/percpu_netfilter_resumed"
local CONTEXT <const> = "softirq"

local runtime <close> = lunatik.runtime(RESUMED, CONTEXT)
runtime:resume()

local runtimes <close> = lunatik.percpu(RESUMED, CONTEXT)
runtimes:resume()

