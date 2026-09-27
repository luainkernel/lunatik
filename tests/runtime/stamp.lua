--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The stamp each runtime of tests/runtime/percpu leaves, and its check (see percpu.sh and percpu_object.sh).

local lunatik = require("lunatik")
local linux   = require("linux")

local PREFIX <const> = "percpu_cpu:"

local stamp = {}

local env = lunatik._ENV

function stamp.leave()
	env[PREFIX .. lunatik.cpu()] = true
end

-- clears the stamps it checks, so the script can run again
function stamp.check()
	assert(env[PREFIX .. linux.numcpus()] == nil, "a runtime ran beyond the last CPU id")
	for cpu = 0, linux.numcpus() - 1 do
		assert(env[PREFIX .. cpu], "no runtime stamped CPU " .. cpu)
		env[PREFIX .. cpu] = nil
	end
end

return stamp

