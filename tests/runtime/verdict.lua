--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Logs what a protected call answered, for a test's shell half to read (see killable.sh).

local verdict = {}

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
function verdict.report(prefix, what, ok, err)
	print(prefix .. what .. " " .. (ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))))
end

return verdict

