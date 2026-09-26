--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A body that raises a table when resumed or spawned, for the errobj test (see errobj.sh).

local function raise()
	error({})
end

return raise

