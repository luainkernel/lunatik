--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Prints the counts of a pinned object's stops, for luaebpf_counts (see common.sh).

local places = assert(require("luaebpf").errors(arg[1]))
for _, place in ipairs(places) do
	print(string.format("%d\t%s:%d: %s", place.count, place.file, place.line, place.reason))
end

