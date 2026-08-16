--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")

if lunatik.cpu() == 1 then
	error("intentional error on the second instance")
end

return function() end

