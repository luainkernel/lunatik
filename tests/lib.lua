--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Helpers shared by the kernel-side test scripts, as tests/lib.sh is by the shell side.

local concat = table.concat
local traceback = debug.traceback

local lib = {}

local function log(what, ...)
	print(concat({what:upper(), ...}, "\t"))
end

--- Runs a test function and prints the result.
-- @tparam string test_name test name.
-- @tparam function func test function to run.
-- @usage test("Test Name", function() ... end)
function lib.test(test_name, func)
	local status, err = pcall(func)
	if status then
		log("pass", test_name)
	else
		log("fail", test_name, err, "\n" .. traceback())
	end
end

return lib

