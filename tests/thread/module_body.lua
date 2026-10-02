--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread module test (see module.sh).

local TIMEOUT <const> = 3000

local function close(sentinel)
	sentinel.closed:complete()
end

local function body(creator, go, closed)
	sentinel = setmetatable({closed = closed}, {__gc = close})
	go:wait(TIMEOUT)
	creator:stop()
end

return body

