--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu object test (see percpu_object.sh).

local lunatik = require("lunatik")
local test    = require("tests.lib").test
local stamp   = require("tests.runtime.stamp")

local body    <const> = "tests/runtime/percpu"
local failing <const> = "tests/runtime/percpu_fail"

test("percpu runs the script once per possible CPU id", function()
	local percpu <close> = lunatik.percpu(body)
	stamp.check()
end)

test("stop closes every runtime and the script runs again", function()
	local percpu = lunatik.percpu(body)
	percpu:stop()
	stamp.check()
	percpu = lunatik.percpu(body)
	stamp.check()
	percpu:stop()
end)

test("stop refuses an object of another class", function()
	local percpu <close> = lunatik.percpu(body)
	local runtime <close> = lunatik.runtime(failing)
	local ok, err = pcall(getmetatable(percpu).stop, runtime)
	assert(not ok, "stop accepted a runtime")
	assert(err:find("lunatik.percpu expected, got lunatik.runtime", 1, true), "stop raised something else: " .. err)
end)

