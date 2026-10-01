--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A body that reads the buffer it is handed and raises a message as long as it, for the gfp test (see gfp.sh).

local rep = string.rep

local function raise(buffer)
	buffer:getstring(0)
	error(rep("x", #buffer), 0)
end

return raise

