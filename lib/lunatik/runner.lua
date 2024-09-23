--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local linux   = require("linux")
local thread  = require("thread")
local rcu     = require("rcu")

local env = lunatik._ENV

local runner = {}

local function trim(script) -- drop ".lua" file extension
	return script:gsub("(%w+).lua", "%1")
end

local function runtime_name(cpu, script)
	return cpu == 0 and script or script .. ":" .. cpu
end

function run(name, script, ...)
	if env.runtimes[name] then
		error(string.format("%s is already running", script))
	end
	local runtime = lunatik.runtime(script, ...)
	env.runtimes[name] = runtime
	return runtime
end

function runner.run(script, ...)
	local script = trim(script)
	return run(script, script, ...)
end

function runner.percpu(script, ...)
	local script = trim(script)
	local runtimes = {}
	local args = {...}
	linux.percpu(function (cpu)
		local name = runtime_name(cpu, script)
		runtimes[name] = run(name, script, table.unpack(args))
	end)
	return runtimes
end

function runner.spawn(script, ...)
	local runtime = runner.run(script, ...)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	env.threads[script] = t
	return t
end

local function stop(registry, script)
	if registry[script] then
		registry[script]:stop()
		registry[script] = nil
	end
end

function runner.stop(script)
	local script = trim(script)
	stop(env.threads, script)
	linux.percpu(function (cpu)
		local name = runtime_name(cpu, script)
		stop(env.runtimes, name)
	end)
end

function runner.list()
	local list = {}
	rcu.map(env.runtimes, function (script)
		table.insert(list, script)
	end)
	return table.concat(list, ', ')
end

function runner.shutdown()
	rcu.map(env.runtimes, function (script)
		runner.stop(script)
	end)
end

function runner.startup()
	env.runtimes = rcu.table()
	env.threads = rcu.table()
end

return runner

