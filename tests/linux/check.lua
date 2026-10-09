--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Assertions shared by the linux scripts (see run.sh).

local check = {}

function check.carries(name, constants, values)
	for key, value in pairs(values) do
		local got = constants[key]
		assert(got == value, ("linux.%s.%s: %s"):format(name, key, tostring(got)))
	end
end

function check.holds(name, constants, names)
	local expected = {}
	for _, key in ipairs(names) do
		assert(constants[key] ~= nil, ("linux.%s.%s is missing"):format(name, key))
		expected[key] = true
	end
	for key in pairs(constants) do
		assert(expected[key], ("linux.%s.%s is outside its family"):format(name, key))
	end
end

return check

