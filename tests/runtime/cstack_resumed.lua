--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the runtime/cstack test (see cstack.sh): the body cstack.lua resumes.
--

local recursion = require("tests.runtime.cstack_recursion")

local function resumed()
	recursion.report("resume", recursion.OVERFLOW, recursion.throughpcall)
end

return resumed

