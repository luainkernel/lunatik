--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier unsupported test (see unsupported.sh).

local notifier = require("notifier")

local function callback() end

local function refuses(name)
	local ok, err = pcall(notifier[name], callback)
	assert(not ok, name .. " registered on a kernel without CONFIG_VT")
	assert(err == "EOPNOTSUPP", name .. ": unexpected error: " .. tostring(err))
end

refuses("keyboard")
refuses("vt")

