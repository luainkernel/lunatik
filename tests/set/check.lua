--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Assertions shared by the set scripts that build a set over bytes (see run.sh).

local check = {}

local keys = {"alpha", "bravo", "charlie", "delta", "echo", "", "alph", "alphaa", "x.alpha", "alpha.",
	"a.b.c", "x.a.b.c", "b.c", "z.b.c", "z.c", "c", "k", "x.k", "ab.c", "nope"}

function check.same(built, expected)
	assert(#built == #expected, "built " .. #built .. " members, set.new of a table built " .. #expected)
	for _, key in ipairs(keys) do
		assert(built:has(key) == expected:has(key), "has('" .. key .. "') differs")
		assert(built:match(key) == expected:match(key),
			"match('" .. key .. "') is " .. built:match(key) .. ", not " .. expected:match(key))
	end
end

function check.raises(expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, "did what should raise " .. expected)
	assert(err:find(expected, 1, true), "raised '" .. tostring(err) .. "', not " .. expected)
end

return check

