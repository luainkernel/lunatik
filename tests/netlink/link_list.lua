--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink link_list test (see link_list.sh).

local netlink = require("netlink")

local link <close> = netlink.rt.link()
for _, iface in ipairs(link:list()) do
	if iface.name == "lo" then
		assert(iface.ifindex == 1, "expected lo ifindex == 1, got " .. tostring(iface.ifindex))
		print("netlink link_list: lo found")
		if iface.mtu and iface.mtu > 0 then
			print("netlink link_list: mtu ok")
		end
		break
	end
end

