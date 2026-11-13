--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/report test (see run.sh).
--

local test = require("tests.lib").test

test("a case that fails on purpose", function()
	error("ELOOP", 0)
end)

