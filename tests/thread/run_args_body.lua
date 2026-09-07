--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread.run() arguments test (see run_args.sh).

local MARKER <const> = "run_args"
local TOKEN <const> = 7

local function body(queue, control, ...)
	local extra = table.pack(...)

	for i = 1, extra.n do
		if #extra[i] ~= i then
			return
		end
	end
	if control:getbyte(0) == TOKEN and control:getbyte(1) == extra.n then
		queue:push(MARKER)
	end
end

return body

