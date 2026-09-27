--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the percpu netfilter test, registration from a resumed body (see percpu_netfilter.sh).

local lunatik = require("lunatik")

local ATTACH  <const> = "tests/runtime/percpu_netfilter_attach"
local CONTEXT <const> = "softirq"

local runtime <close> = lunatik.runtime(ATTACH, CONTEXT)
runtime:resume()

local runtimes <close> = lunatik.percpu(ATTACH, CONTEXT)
runtimes:resume()

