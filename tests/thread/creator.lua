--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Runtime that starts a thread for the thread tests (see run.sh): it threads the runtime it is
-- resumed with, hands the body the objects after it, and hands the thread back.

local thread = require("thread")

local NAME <const> = "lunatik_creator"

local function creator(runtime, ...)
	return thread.run(runtime, NAME, ...)
end

return creator

