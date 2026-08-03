--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")
local test    = require("util").test

local zombie <const> = "tests/runtime/percpu_fail:0"

test("percpu rollback leaves no instances behind", function()
	assert(lunatik._ENV.runtimes[zombie] == nil, "instance 0 survived the failed run")
end)

