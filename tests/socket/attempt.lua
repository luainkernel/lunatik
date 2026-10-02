--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A socket constructor whose socket is closed at once, shared by the socket scripts that ask only what it answers
-- (see address.sh, packet.sh and raw.sh).

local attempt = {}

function attempt.new(new, ...)
	local ok, sock = pcall(new, ...)
	if ok then
		sock:close()
	end
	return ok, sock
end

return attempt

