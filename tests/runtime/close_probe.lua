--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Hardirq runtime of the close test (see close.sh): a probe is stopped while the body loads.

local probe = require("probe")

local SYMBOL <const> = "vfs_read"

local handle = probe.new(SYMBOL, {})
local class = getmetatable(handle)
assert(class.__close == class.stop, "a probe's __close is not its stop")

do
	local held <close> = handle
end

local ok, err = pcall(handle.enable, handle, true)
assert(not ok and tostring(err):match("closed object"), "a to-be-closed probe still enables")

