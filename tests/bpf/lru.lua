--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf LRU hash map test (see run.sh).

local map = require("bpf").map
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map_lru"

test("bpf.map lru round-trip", function()
	local m = map(path)
	assert(m:info().type == bpf.MAP_TYPE_LRU_HASH, "expected LRU hash map type")
	assert(m:update("aaa", "vvv"))
	local value = m:lookup("aaa")
	assert(value == "vvv", "expected 'vvv', got: " .. tostring(value))
	assert(m:remove("aaa") == "vvv", "expected removed value")
	assert(m:delete("aaa") == false, "expected false after remove")
	m:close()
end)

