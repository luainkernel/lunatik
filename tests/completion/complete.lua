--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Completer sub-script for the completion deferred test (see run.sh).

local function complete(event)
	event:complete()
	event:complete()
end

return complete

