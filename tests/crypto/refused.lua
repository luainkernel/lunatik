--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The refusal check the crypto large scripts share (see large.sh).

local function refused(expected, name, method, c, ...)
	local ok, err = pcall(method, c, ...)
	assert(not ok, name .. " should be refused")
	assert(err == expected, name .. ": expected '" .. expected .. "', got: " .. tostring(err))
end

return refused

