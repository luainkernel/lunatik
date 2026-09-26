--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the errobj test (see errobj.sh).

local lunatik = require("lunatik")
local device  = require("device")

local MESSAGE <const> = "error object is not a string"

local driver = {name = "lunatik_errobj"}

function driver:read()
	error({})
end

local ok, err = pcall(lunatik.runtime, "tests/runtime/errobj_load")
assert(not ok and err == MESSAGE, "a script raising a table as it loads answered " .. tostring(err))

local runtime = lunatik.runtime("tests/runtime/errobj_raise")
ok, err = pcall(runtime.resume, runtime)
assert(not ok and err == MESSAGE .. "\n", "a resume raising a table answered " .. tostring(err))

device.new(driver)

