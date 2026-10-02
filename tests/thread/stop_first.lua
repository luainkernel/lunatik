--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread stop test (see stop.sh): the first of two concurrent stops.

local FIRST <const> = "first"

local function body(t, shared, stopped)
	local ok, result = pcall(t.stop, t)
	shared[FIRST] = ok and result
	stopped:complete()
end

return body

