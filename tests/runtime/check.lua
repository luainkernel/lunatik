--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Assertions shared by the runtime scripts (see foreign_method.sh, opt_guards.sh and resume_results.sh).

local data = require("data")

local check = {}

local foreign = data.new(8)

function check.raises(fn, pattern)
	local ok, err = pcall(fn)
	assert(not ok, "expected error but got none")
	assert(err:find(pattern), "unexpected error: " .. tostring(err))
end

function check.refused(name, method, ...)
	local ok, err = pcall(method, foreign, ...)
	assert(not ok, name .. " accepted a data object")
	assert(err:match("expected"), name .. " raised something else: " .. err)
end

return check

