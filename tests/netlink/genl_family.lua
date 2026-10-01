--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink genl_family test (see genl_family.sh).

local netlink   = require("netlink")
local message   = require("netlink.message")
local genetlink = require("linux.genl")

local ctrl = genetlink.ctrl

local genl <close> = netlink.genl()
local id = genl:family("nlctrl")
assert(id == genetlink.id.CTRL, "expected nlctrl id == " .. genetlink.id.CTRL .. ", got " .. tostring(id))
print("netlink genl_family: nlctrl resolved")

-- a second operation on the SAME instance must work: family() and talk() must
-- drain the NLM_F_ACK so the socket stays in sync (regression for orphaned ACK)
local msgs = genl:talk(genetlink.id.CTRL, ctrl.cmd.GETFAMILY,
	message.attrs{[ctrl.attr.FAMILY_NAME] = string.pack("z", "nlctrl")})
local fid
for _, m in ipairs(msgs) do fid = fid or m.attrs[ctrl.attr.FAMILY_ID] end
assert(fid and string.unpack("=I2", fid) == id, "talk() GETFAMILY did not return the family id")
print("netlink genl_family: talk round-trip ok")

-- dump: a GETFAMILY with no family name lists every registered family; nlctrl
-- must be among them, and each entry carries its decoded attributes
local families = genl:dump(genetlink.id.CTRL, ctrl.cmd.GETFAMILY)
assert(#families > 0, "dump returned no families")
local found
for _, m in ipairs(families) do
	local name = m.attrs[ctrl.attr.FAMILY_NAME]
	if name and string.unpack("z", name) == "nlctrl" then found = true end
end
assert(found, "dump did not list the nlctrl family")
print("netlink genl_family: dump lists families")

-- the controller's attributes, without the attributes of the nests they carry
assert(ctrl.attr.FAMILY_ID == 1 and ctrl.attr.OP == 10, "linux.genl.ctrl.attr lost a controller attribute")
for _, nested in ipairs{"OP_ID", "MCAST_GRP_NAME", "POLICY_DO", "MAX"} do
	assert(ctrl.attr[nested] == nil, "linux.genl.ctrl.attr carries " .. nested)
end
print("netlink genl_family: ctrl.attr holds the controller's attributes")

-- an unknown family raises
assert(not pcall(genl.family, genl, "nosuchfamily_xyz"), "expected error resolving a missing family")
print("netlink genl_family: missing family errors")

