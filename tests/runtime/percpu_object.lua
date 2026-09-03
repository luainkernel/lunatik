--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu object test (see percpu_object.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local body    <const> = "tests/runtime/percpu"
local failing <const> = "tests/runtime/percpu_fail"
local stamp   <const> = "percpu_cpu:"

local env = lunatik._ENV

local function stamped()
	assert(env[stamp .. linux.numcpus()] == nil, "an instance ran beyond the last CPU id")
	for cpu = 0, linux.numcpus() - 1 do
		assert(env[stamp .. cpu], "no instance stamped CPU " .. cpu)
		env[stamp .. cpu] = nil
	end
end

test("percpu runs the script once per possible CPU id", function()
	local percpu <close> = lunatik.percpu(body)
	stamped()
end)

test("stop closes every instance and the script runs again", function()
	local percpu = lunatik.percpu(body)
	percpu:stop()
	stamped()
	percpu = lunatik.percpu(body)
	stamped()
	percpu:stop()
end)

test("stop refuses an object of another class", function()
	local percpu <close> = lunatik.percpu(body)
	local runtime <close> = lunatik.runtime(failing)
	local ok, err = pcall(getmetatable(percpu).stop, runtime)
	assert(not ok, "stop accepted a runtime")
	assert(err:match("percpu expected"), "stop raised something else: " .. err)
end)

if linux.numcpus() > 1 then
	test("a failing instance raises with its error", function()
		local ok, err = pcall(lunatik.percpu, failing)
		assert(not ok, "percpu returned an object for a failing script")
		assert(err:match("intentional error on the second instance"), "unexpected error: " .. err)
	end)
end

