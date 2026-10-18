--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The blocks the vfree test frees with interrupts off, run in a hardirq runtime (see vfree.sh).

local sizes = require("tests.runtime.vfree_sizes")

local strings = {string.rep("x", sizes.vmalloc)}

local function free(buffer)
	table.remove(strings)
	collectgarbage()
	buffer:resize(1)
end

return free

