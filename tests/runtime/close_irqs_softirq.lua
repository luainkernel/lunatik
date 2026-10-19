--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq runtime of tests/runtime/close_irqs.sh (runtime/close_irqs/softirq).

local function close(queue, scoped)
	queue:close()
	local held <close> = scoped
end

return close

