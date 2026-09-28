--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The stamp each runtime of tests/runtime/percpu leaves, and its check (see percpu.sh and percpu_object.sh).

local lunatik = require("lunatik")
local cpu     = require("cpu")

local PREFIX <const> = "percpu_cpu:"

local stamp = {}

local env = lunatik._ENV

function stamp.leave()
	env[PREFIX .. lunatik.cpu()] = true
end

-- clears the stamps it checks, so the script can run again
function stamp.check()
	assert(env[PREFIX .. cpu.maxid() + 1] == nil, "a runtime ran beyond the last CPU id")
	for id in cpu.possible() do
		assert(env[PREFIX .. id], "no runtime stamped CPU " .. id)
		env[PREFIX .. id] = nil
	end
end

return stamp

