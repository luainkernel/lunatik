--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The blocklist of the SNI filter; examples/filter/sni.bpf.lua is the program that reads it.

local map = require("bpf.map")

local BLOCKED <const> = "/sys/fs/bpf/lunatik/examples/filter/sni/blocked"
local KEY     <const> = "c64"
local VALUE   <const> = "I8"
local UNSEEN  <const> = 0

local blocklist = {
	"ebpf.io",
}

-- the loader pinned the map before this ran, so it opens by the path the program declared it under
local blocked <close> = map.hash(BLOCKED, KEY, VALUE)

for _, host in ipairs(blocklist) do
	blocked[host] = UNSEEN
end

