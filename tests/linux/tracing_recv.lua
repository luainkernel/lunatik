--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the linux.tracing test (see run.sh).
--

local linux = require("linux")

local function toggle()
	assert(linux.tracing(false) == false and linux.tracing() == false, "an armed runtime did not turn tracing off")
	assert(linux.tracing(true) == true and linux.tracing() == true, "an armed runtime did not turn tracing on")
end

return toggle

