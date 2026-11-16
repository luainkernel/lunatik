--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script that reads the scx pass test's record (see run.sh).

local map  = require("bpf.map")
local cpu  = require("cpu")
local test = require("tests.lib").test
local env  = require("lunatik")._ENV

-- the values linux/sched/ext.h gives, apart from linux.scx, which pass.lua answers with
local GLOBAL    <const> = 0x8000000000000001
local LOCAL     <const> = 0x8000000000000002
local LOCAL_ON  <const> = 0xc000000000000000
local SLICE_DFL <const> = 20000000
local SLICE_INF <const> = 0xffffffffffffffff
local SLICE     <const> = 5000000            -- pass.lua's SLICE
local UNSET     <const> = 0x5c5c5c5c5c5c5c5c -- scx_pass.bpf.c's CLS_UNSET
local KEPT      <const> = {-1, UNSET, UNSET}
local RESUMED   <const> = "scx resumed"      -- resume.lua's KEY

local last -- the CPU run.sh pins scx_local_on to
for id in cpu.online() do
	last = id
end

local expected = {
	scx_none       = KEPT,
	scx_raise      = KEPT,
	scx_nil_dsq    = {0, GLOBAL, SLICE},
	scx_nil_slice  = {0, LOCAL, SLICE_DFL},
	scx_str_dsq    = KEPT,
	scx_bool_slice = KEPT,
	scx_local      = {0, LOCAL, SLICE_INF},
	scx_global     = {0, GLOBAL, SLICE},
	scx_local_on   = {0, LOCAL_ON | last, SLICE_INF},
	scx_detach     = {0, GLOBAL, SLICE},
	scx_after      = KEPT,
}

local function show(r)
	return ("%d, cls {%#x, %#x}"):format(r[1], r[2], r[3])
end

local resumed = env[RESUMED]
env[RESUMED] = nil

test("scx_keep", function()
	assert(resumed ~= nil, "resume.lua left no record")
	print(("scx record: scx_keep raised for its ctx %s, for its task %s"):format(resumed.ctx, resumed.task))
	assert(resumed.ctx, "the kept ctx did not raise ctx is not set")
	assert(resumed.task, "the kept task did not raise closed object")
end)

local record <close> = map.hash("/sys/fs/bpf/scx_record", "c16", "i8i8i8")

for comm, want in pairs(expected) do
	test(comm, function()
		local got = assert(record[comm], "no enqueue recorded")
		print(("scx record: %s returned %s"):format(comm, show(got)))
		assert(got[1] == want[1] and got[2] == want[2] and got[3] == want[3], "expected " .. show(want))
	end)
end

