--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- What the bpf scripts share about the maps run.sh pins: the sizes it creates them with, and a drain.

local pinned = {}

local VALUE   <const> = 3
local ENTRIES <const> = 128

function pinned.drain(m)
	while m:pop() do
	end
end

function pinned.checkinfo(m, maptype, keysize)
	local info = m:info()
	assert(info.type == maptype, "expected map type " .. maptype .. ", got " .. info.type)
	assert(info.key_size == keysize, "expected key_size " .. keysize)
	assert(info.value_size == VALUE, "expected value_size " .. VALUE)
	assert(info.max_entries == ENTRIES, "expected max_entries " .. ENTRIES)
end

return pinned

