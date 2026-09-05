--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the runtime class check test (see resume_foreign.sh).

local lunatik = require("lunatik")
local data    = require("data")
local test    = require("util").test

local SCRIPT <const> = "tests/runtime/resume_shared_recv"

test("resume refuses an object of another class", function()
	local runtime <close> = lunatik.runtime(SCRIPT)
	local ok, err = pcall(getmetatable(runtime).resume, data.new(8))
	assert(not ok, "resume accepted a data object")
	assert(err:match("runtime expected"), "resume raised something else: " .. err)
end)

