--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Pacing shared by the kernel threads of object_grace and map_sync (see object_grace.sh and map_sync.sh).

local linux = require("linux")

local SLICE_NS <const> = 10 * 1000000
local NAP_MS   <const> = 1

local pace = {}

local slice = linux.time() + SLICE_NS

-- once per slice, not per turn: each pause lasts up to a tick, and one per turn leaves the threads mostly asleep
function pace.yield()
	if linux.time() >= slice then
		linux.schedule(NAP_MS)
		slice = linux.time() + SLICE_NS
	end
end

return pace

