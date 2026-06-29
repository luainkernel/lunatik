--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink link_dump test (see link_dump.sh).

local rt = require("netlink.rt")

local r <close> = rt()
for _, link in ipairs(r:link_dump()) do
	if link.name == "lo" then
		assert(link.ifindex == 1, "expected lo ifindex == 1, got " .. tostring(link.ifindex))
		print("netlink link_dump: lo found")
		if link.mtu and link.mtu > 0 then
			print("netlink link_dump: mtu ok")
		end
		break
	end
end

