--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu runtime test (see percpu.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local prefix <const> = "tests/runtime/percpu:"

test("percpu registers one runtime per possible CPU id", function()
	local runtimes = lunatik._ENV.runtimes
	for cpu = 0, linux.numcpus() - 1 do
		assert(runtimes[prefix .. cpu] ~= nil, "missing runtime for CPU " .. cpu)
	end
	assert(runtimes[prefix .. linux.numcpus()] == nil, "runtime beyond the last CPU id")
end)

