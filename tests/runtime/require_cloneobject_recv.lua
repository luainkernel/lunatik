--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the require_cloneobject test (see require_cloneobject.sh).

package.searchers = {}

local function recv(object)
	local name = getmetatable(object).__name
	assert(package.loaded[name] == nil, "cloning a " .. name .. " added it to package.loaded")
end

return recv

