--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread release test (see release.sh).

local function close(sentinel)
	sentinel.closed:complete()
end

local function body(done, closed)
	sentinel = setmetatable({closed = closed}, {__gc = close})
	done:complete()
end

return body

