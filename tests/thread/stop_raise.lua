--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread stop test (see stop.sh).

local MESSAGE <const> = "the body raises"

local function body(running)
	running:complete()
	error(MESSAGE, 0)
end

return body

