--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- What the bpf scripts share about the maps run.sh pins: the sizes it creates them with, a drain,
-- and the class names a handle carries.

local data = require("data")

local pinned = {}

local VALUE   <const> = 3
local ENTRIES <const> = 128
local CLASSES <const> = "bpf.hash or bpf.queue"

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

function pinned.checkclass(m, class)
	assert(getmetatable(m).__name == class, "expected class " .. class)
	local ok, err = pcall(m.info, data.new(1))
	assert(not ok, "info accepted an object of another class")
	assert(err:find(CLASSES .. " expected, got data", 1, true), "info raised something else: " .. err)
end

return pinned

