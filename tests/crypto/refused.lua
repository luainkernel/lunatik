--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto refused test (see refused.sh).

local crypto = require("crypto")
local test   = require("tests.lib").test

local case = require("tests.crypto.refused_case")
local class, name, refused = case.class, case.name, case.errno

test("crypto." .. class .. " raises " .. refused .. " for " .. name, function()
	local ok, err = pcall(crypto[class], name)
	assert(not ok, "crypto." .. class .. " allocated " .. name)
	assert(err == refused, "crypto." .. class .. " raised " .. tostring(err) .. " where " .. refused .. " was expected")
end)

