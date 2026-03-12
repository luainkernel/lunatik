--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the resume_shared regression test.
-- Receives a fifo object passed via runtime:resume() and verifies it is valid.

local function recv(f)
	assert(f:pop(13) == "hello kernel!")
end

return recv

