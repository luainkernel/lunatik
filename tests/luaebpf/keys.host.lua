--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Prints the runtime's name each call in a disassembly stores, for the callback case (see callback.sh).

local order = os.getenv("ORDER") == "big" and ">i8" or "<i8"
local stored, value, base = {}, nil, nil
for line in io.lines() do
	local held, at = line:match("r1 = (%S+)"), line:match("%(r10 %- (%d+)%) = r1$")
	local size = base and tonumber(line:match("r2 = (%d+)$") or "")
	if held then
		value = tonumber(held)
	elseif at then
		stored[tonumber(at)] = value
	elseif size then
		local words = {}
		for slot = base, base - size + 1, -8 do
			table.insert(words, string.pack(order, stored[slot]))
		end
		print(table.concat(words):sub(1, size - 1))
	end
	base = tonumber(line:match("r1 %+= %-(%d+)$") or "")
end

