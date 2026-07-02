--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink route_dump test (see route_dump.sh).

local rt = require("netlink.rt")

local r <close> = rt()
local routes = r:route_dump()

if #routes > 0 then
	print("netlink route_dump: routes found")
end

local first = routes[1]
if first and first.family ~= nil and first.scope ~= nil and first.rtype ~= nil then
	print("netlink route_dump: fields ok")
end

