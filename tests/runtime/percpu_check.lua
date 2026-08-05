--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local script <const> = "tests/runtime/percpu"
local prefix <const> = script .. ":"

test("percpu registers one runtime per possible CPU id", function()
	local percpu = lunatik._ENV.percpu
	for cpu = 0, linux.numcpus() - 1 do
		assert(percpu[prefix .. cpu] ~= nil, "missing runtime for CPU " .. cpu)
	end
	assert(percpu[prefix .. linux.numcpus()] == nil, "runtime beyond the last CPU id")
	assert(lunatik._ENV.runtimes[script] == nil, "percpu script leaked into env.runtimes")
end)

test("each instance sees its own CPU id, a plain runtime sees none", function()
	assert(lunatik.cpu() == nil, "plain runtime reports a CPU id")
	for cpu = 0, linux.numcpus() - 1 do
		assert(lunatik._ENV["percpu_cpu:" .. cpu], "no instance stamped CPU " .. cpu)
		lunatik._ENV["percpu_cpu:" .. cpu] = nil
	end
end)

