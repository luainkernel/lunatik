--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the resume/thread chaining test: the attacher returns the
-- thread body, as the echod worker does, and resume must leave it on the stack.

local MESSAGE <const> = "resumed and spawned"

local function attacher(queue)
	return function ()
		queue:push(MESSAGE)
	end
end

return attacher

