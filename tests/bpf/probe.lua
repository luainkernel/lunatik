--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Cases described in tests/bpf/run.sh (bpf/probe).

local bpf    = require("bpf")
local probe  = require("probe")
local systab = require("syscall.table")

local HASH    <const> = "/sys/fs/bpf/test_map"
local QUEUE   <const> = "/sys/fs/bpf/test_map_queue"
local REFUSAL <const> = "not allowed with IRQs disabled"

local function refused(map)
	local ok, err = pcall(map.close, map)
	return not ok and err == REFUSAL and pcall(map.info, map)
end

bpf.hash(HASH):close()
bpf.queue(QUEUE):close()

local hash, queue = bpf.hash(HASH), bpf.queue(QUEUE)

local function pre()
	print("bpf probe: " .. ((refused(hash) and refused(queue)) and "refused" or "closed"))
end

probe.new(systab["personality"], {pre = pre})

