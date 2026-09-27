--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread self_stop test (see self_stop.sh): yields, then
-- stops the thread it is resumed with.

local PREFIX <const> = "thread self_stop test: "

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local function body(ready)
	ready:complete()
	local t = coroutine.yield()
	print(PREFIX .. "resumed stop " .. verdict(pcall(t.stop, t)))
end

return body

