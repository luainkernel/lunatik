--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the percpu resume test (see resume_percpu.sh).

local lunatik = require("lunatik")

local function recv(first, second)
	local cpu = tostring(lunatik.cpu())

	first[cpu] = 1
	if second ~= nil then
		second[cpu] = 2
	end
	coroutine.yield(first)
	first[cpu] = nil
end

return recv

