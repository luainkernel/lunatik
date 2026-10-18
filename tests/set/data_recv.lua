--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the set.fromdata test (see run.sh).

local function recv(s)
	assert(#s == 4 and s:has("b.c") and not s:has("a.b"), "the set lost its members")
	assert(s:match("x.a.b.c") == 4 and s:match("z.c") == 1 and s:match("k") == 4294967295, "the set lost its labels")
end

return recv

