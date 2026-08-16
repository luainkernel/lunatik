--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local script <const> = "tests/runtime/percpu"
local stamp  <const> = "percpu_cpu:"

local env = lunatik._ENV

test("percpu registers one object, running the script on every CPU id", function()
	assert(env.runtimes[script] ~= nil, "the percpu script is not registered")
	assert(env[stamp .. linux.numcpus()] == nil, "an instance ran beyond the last CPU id")
	for cpu = 0, linux.numcpus() - 1 do
		assert(env[stamp .. cpu], "no instance stamped CPU " .. cpu)
		env[stamp .. cpu] = nil
	end
end)

test("a plain runtime has no CPU id", function()
	assert(lunatik.cpu() == nil, "plain runtime reports a CPU id")
end)

