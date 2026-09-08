--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the newobject_oom test (see newobject_oom.sh).

local lunatik = require("lunatik")
local test    = require("util").test

local SCRIPT <const> = "tests/rcu/newobject_oom_atomic"

test("a failed private allocation surfaces as an error", function()
	local runtime <close> = lunatik.runtime(SCRIPT, "softirq")
	runtime:resume() -- closing the runtime afterwards runs the failed object's finalizer
end)

