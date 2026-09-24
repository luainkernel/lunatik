--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the owned test (see owned.sh).

local device = require("device")

local NAME <const> = "lunatik_owned"

local dev = device.new{name = NAME}
local registry = debug.getregistry()

for key, value in pairs(registry) do
	if value == dev then registry[key] = nil end
end
dev = nil
collectgarbage()

