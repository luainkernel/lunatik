--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Clock and pacing shared by the kernel threads of object_grace and map_sync (see object_grace.sh and map_sync.sh).

local linux = require("linux")

local SLICE_MS <const> = 10
local NAP_MS   <const> = 1

local pace = {}

function pace.milliseconds()
	return linux.time() // 1000000
end

local slice = pace.milliseconds() + SLICE_MS

-- once per slice, not per turn: each pause lasts up to a tick, and one per turn leaves the threads mostly asleep
function pace.yield()
	if pace.milliseconds() >= slice then
		linux.schedule(NAP_MS)
		slice = pace.milliseconds() + SLICE_MS
	end
end

return pace

