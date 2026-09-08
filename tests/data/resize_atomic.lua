--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the failed-resize test (see resize_atomic.sh).
-- Holds the atomic runtime in a global so its buffer outlives the run and the
-- harness can measure it; stopping the script frees it.

local lunatik = require("lunatik")
local test    = require("util").test

local SCRIPT <const> = "tests/data/resize_atomic_grow"

ATOMIC = lunatik.runtime(SCRIPT, "softirq")

test("a failed resize leaves the object on its buffer", function()
	ATOMIC:resume()
end)

