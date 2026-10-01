--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the library reopen test (see require_reopen.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local test    = require("tests.lib").test

test("a library opened after a clone of its class keeps the class metatables", function()
	assert(package.loaded["rcu.table"] == nil, "_ENV registered the library under its class name")
	assert(getmetatable(lunatik._ENV) == getmetatable(rcu.table()), "the open replaced the class metatable")
end)

