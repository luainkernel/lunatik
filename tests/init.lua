--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local function run_test(test_name, func)
	local status, err = pcall(func)
	if status then
		print(string.format("[PASS] %s", test_name))
	else
		print(string.format("[FAIL] %s: %s\n%s", test_name, err, debug.traceback()))
	end
end

return {
	run_test = run_test,
}

