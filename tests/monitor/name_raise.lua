--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A body that raises a message carrying a question mark when resumed, for the name test (see name.sh).

local function raise()
	error("ready?", 0)
end

return raise

