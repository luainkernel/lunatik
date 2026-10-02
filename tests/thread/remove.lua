--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Runtime that removes the creator an rcu.table holds, for the thread atomic test (see atomic.sh).

local function remove(shared)
	shared.creator = nil
end

return remove

