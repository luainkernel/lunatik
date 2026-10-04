--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq runtime of the close test (see close.sh): a notifier is stopped while the body loads.

local notifier = require("notifier")

local function ignore()
end

local block = notifier.netdevice(ignore)
local class = getmetatable(block)
assert(class.__close == class.stop, "a notifier's __close is not its stop")

do
	local held <close> = block
end

block:stop()

