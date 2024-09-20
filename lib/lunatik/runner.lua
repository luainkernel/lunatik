--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local thread  = require("thread")
local rcu     = require("rcu")

local env = lunatik._ENV

local runner = {}

local function trim(script) -- drop ".lua" file extension
	return script:gsub("(%w+).lua", "%1")
end

function runner.run(script, ...)
	local script = trim(script)
	if env.runtimes[script] then
		error(string.format("%s is already running", script))
	end
	local runtime = lunatik.runtime(script, ...)
	env.runtimes[script] = runtime
	return runtime
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
	stop(env.runtimes, script)
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

