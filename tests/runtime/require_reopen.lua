--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the library reopen test (see require_reopen.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local test    = require("util").test

test("a library opened again under another name keeps its classes", function()
	assert(package.loaded["rcu.table"], "_ENV did not register the library under its class name")
	assert(getmetatable(lunatik._ENV) == getmetatable(rcu.table()), "the second open replaced the class metatable")
end)

