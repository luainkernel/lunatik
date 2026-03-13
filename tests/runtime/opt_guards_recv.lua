--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the opt_guards test.
-- Accepts any shareable object passed via resume() and discards it.
-- Loops with yield to stay alive across multiple resume() calls.

local function recv(obj)
	while true do
		assert(obj ~= nil, "expected a shared object")
		obj = coroutine.yield()
	end
end

return recv
