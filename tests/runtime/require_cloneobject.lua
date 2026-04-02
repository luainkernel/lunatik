--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the require_cloneobject regression test (see require_cloneobject.sh).

local lunatik = require("lunatik")
local data    = require("data")

local d = data.new(4)
d:setuint32(0, 0xdeadbeef)

local rt = lunatik.runtime("tests/runtime/require_cloneobject_recv", "softirq")
local ok, err = pcall(rt.resume, rt, d)
if not ok then
	error("lunatik_require failed: " .. tostring(err))
end

