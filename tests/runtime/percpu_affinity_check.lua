--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu affinity test (see percpu_affinity.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local PACKETS <const> = 7  -- must match percpu_affinity.sh

test("each packet is handled by exactly one percpu instance", function()
	local total = 0
	for cpu = 0, linux.numcpus() - 1 do
		local count = lunatik._ENV["percpu_nf:" .. cpu] or 0
		total = total + count
		lunatik._ENV["percpu_nf:" .. cpu] = nil
	end
	assert(total == PACKETS,
		string.format("expected %d handled packets, got %d", PACKETS, total))
end)

