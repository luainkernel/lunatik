--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the percpu resume test (see resume_percpu.sh).

local function recv(delivered)
	while true do
		if delivered == nil then
			error("nothing was delivered")
		end
		delivered = coroutine.yield()
	end
end

return recv

