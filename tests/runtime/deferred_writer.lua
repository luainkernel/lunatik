--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Writer script for the deferred test (see deferred.sh), run in a softirq or a hardirq runtime.

local function remove(entries)
	entries.child = nil -- the child's last reference, dropped under this runtime's lock
end

return remove

