--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink genl_family test (see genl_family.sh).

local genl = require("netlink.genl")
local const = require("linux.genl")

local g <close> = genl()
local id = g:family("nlctrl")
assert(id == const.id.CTRL,
	"expected nlctrl id == " .. const.id.CTRL .. ", got " .. tostring(id))
print("netlink genl_family: nlctrl resolved")

