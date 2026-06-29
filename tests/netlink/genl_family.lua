--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink genl_family test (see genl_family.sh).

local genl    = require("netlink.genl")
local message = require("netlink.message")
local ctrl    = require("linux.genl")

local g <close> = genl()
local id = g:family("nlctrl")
assert(id == ctrl.id.CTRL, "expected nlctrl id == " .. ctrl.id.CTRL .. ", got " .. tostring(id))
print("netlink genl_family: nlctrl resolved")

-- a second operation on the SAME instance must work: family() and call() must
-- drain the NLM_F_ACK so the socket stays in sync (regression for orphaned ACK)
local msgs = g:call(ctrl.id.CTRL, ctrl.cmd.GETFAMILY, 0,
	message.attrs{[ctrl.attr.FAMILY_NAME] = string.pack("z", "nlctrl")})
local fid
for _, m in ipairs(msgs) do fid = fid or m.attrs[ctrl.attr.FAMILY_ID] end
assert(fid and string.unpack("=I2", fid) == id, "call() GETFAMILY did not return the family id")
print("netlink genl_family: call round-trip ok")

-- dump: a GETFAMILY with no family name lists every registered family; nlctrl
-- must be among them, and each entry carries its decoded attributes
local families = g:dump(ctrl.id.CTRL, ctrl.cmd.GETFAMILY)
assert(#families > 0, "dump returned no families")
local found
for _, m in ipairs(families) do
	local name = m.attrs[ctrl.attr.FAMILY_NAME]
	if name and string.unpack("z", name) == "nlctrl" then found = true end
end
assert(found, "dump did not list the nlctrl family")
print("netlink genl_family: dump lists families")

-- an unknown family raises
assert(not pcall(g.family, g, "nosuchfamily_xyz"), "expected error resolving a missing family")
print("netlink genl_family: missing family errors")

