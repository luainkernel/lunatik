--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the percpu resume test (see resume_percpu.sh).

local function recv()
	error("intentional error on resumption")
end

return recv

