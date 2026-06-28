--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink addr_dump test (see addr_dump.sh).

local rt = require("netlink.rt")
local af = require("linux.socket").af

local function is_loopback(addr)
	if not addr or #addr < 4 then return false end
	local b1, b2, b3, b4 = addr:byte(1, 4)
	return b1 == 127 and b2 == 0 and b3 == 0 and b4 == 1
end

local r <close> = rt()
for _, addr in ipairs(r:addr_dump(af.INET)) do
	if is_loopback(addr.address) then
		print("netlink addr_dump: 127.0.0.1 found")
		if addr.prefix_len == 8 then
			print("netlink addr_dump: prefix_len ok")
		end
		break
	end
end

