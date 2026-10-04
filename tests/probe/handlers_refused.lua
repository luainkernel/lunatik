--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, handlers that are not functions (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local test   = require("tests.lib").test
local format = string.format

local notfunctions = {42, "pre", {}}

test("probe.new refuses a pre or a post that is not a function", function()
	for _, field in ipairs({"pre", "post"}) do
		for _, value in ipairs(notfunctions) do
			local ok, err = pcall(probe.new, systab["personality"], {[field] = value})
			local expected = format("bad field '%s' %%(function expected, got %s%%)", field, type(value))
			assert(not ok and err:match(expected), "probe.new took " .. field .. " = " .. tostring(value))
		end
	end
end)

