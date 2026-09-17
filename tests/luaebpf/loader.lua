--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the loader test (see load.sh).

local map = require("bpf.map")

local COUNTS <const> = "/sys/fs/bpf/lunatik/tests/luaebpf/loader/counts"
local SEEN   <const> = 0

local counts <close> = map.array(COUNTS, "I4", "I8")

print("luaebpf loader test pass: counts[" .. SEEN .. "] is " .. tostring(counts[SEEN]))

