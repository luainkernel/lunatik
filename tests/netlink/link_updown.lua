--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink link_updown test (see link_updown.sh).

local netlink = require("netlink")
local iff     = require("linux.rtnetlink").iff

local NAME <const> = "lunatikdummy0"

local link <close> = netlink.rt.link()

local function find()
	for _, iface in ipairs(link:list()) do
		if iface.name == NAME then return iface end
	end
end

local iface = find()
assert(iface, NAME .. " not found")
assert(iface.flags & iff.UP == 0, "interface should start down")

link:set{ifindex = iface.ifindex, up = true}
assert(find().flags & iff.UP ~= 0, "interface did not come up")
print("netlink link_updown: brought up")

link:set{ifindex = iface.ifindex, up = false}
assert(find().flags & iff.UP == 0, "interface did not go down")
print("netlink link_updown: brought down")

