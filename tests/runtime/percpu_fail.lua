--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")

local env = lunatik._ENV
local count = (env.percpu_fail_count or 0) + 1
env.percpu_fail_count = count
if count == 2 then
	env.percpu_fail_count = nil
	error("intentional error on the second instance")
end

return function() end

