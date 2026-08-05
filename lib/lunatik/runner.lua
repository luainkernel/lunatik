--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Manages the execution and lifecycle of Lunatik scripts.
-- This module provides functionalities to run scripts as isolated runtimes,
-- spawn them into separate kernel threads, and manage their state (start, stop, list, shutdown).
-- It uses RCU-safe tables to store references to active runtimes and threads.
-- In following descriptions, 'env' variable stands for 'lunatik._ENV'.
--
-- @module lunatik.runner

local lunatik = require("lunatik")
local thread  = require("thread")
local rcu     = require("rcu")
local linux   = require("linux")

local env = lunatik._ENV

local runner = {}

--- Removes the ".lua" extension from a script filename.
-- @local
-- @function trim
-- @tparam string script script filename (e.g., "myscript.lua").
-- @treturn string script name without the ".lua" extension (e.g., "myscript").
local function trim(script) -- drop ".lua" file extension
	return script:gsub("(%w+).lua", "%1")
end

local function key(script, cpu)
	return script .. ":" .. cpu
end

local function ispercpukey(script)
	local base = string.match(script, "^(.+):%d+$")
	return base ~= nil and env.percpu[base] ~= nil
end

--- Stops an item (runtime or thread) in the given registry.
-- If the item exists in the registry, its `stop()` method is called,
-- and it's removed from the registry.
-- @local
-- @function stop
-- @tparam table registry registry table (e.g., `env.threads` or `env.runtimes`).
-- @tparam string script key (script name) of the item to stop.
local function stop(registry, script)
	if registry[script] then
		registry[script]:stop()
		registry[script] = nil
	end
end

--- Runs a Lunatik script in the current context.
-- Creates a new Lunatik runtime for the given script and registers it.
-- Throws an error if a script with the same name is already running.
-- @tparam string script path or name of the Lua script to run. The ".lua" extension will be trimmed.
-- @tparam[opt] string context Execution context: `"process"` (default) or `"softirq"` (for netfilter/XDP hooks).
-- @tparam[opt] boolean percpu create one runtime per CPU id, registered as `<script>:<cpu>`,
--   for scripts dispatched by the eBPF bindings; the script runs once per runtime.
-- @treturn table created Lunatik runtime object, or `nil` when `percpu` is set.
-- @raise error if the script is already running.
function runner.run(script, context, percpu, ...)
	local script = trim(script)
	if env.runtimes[script] or env.percpu[script] then
		error(string.format("%s is already running", script))
	end
	if percpu then
		for cpu = 0, linux.numcpus() - 1 do
			local ok, runtime = pcall(lunatik.runtime, script, context, ...)
			if not ok then
				for created = 0, cpu - 1 do
					stop(env.runtimes, key(script, created))
				end
				error(runtime, 0)
			end
			env.runtimes[key(script, cpu)] = runtime
		end
		env.percpu[script] = true
		return nil
	end
	local runtime = lunatik.runtime(script, context, ...)
	env.runtimes[script] = runtime
	return runtime
end

--- Spawns a Lunatik script in a new kernel thread.
-- First, it runs the script using `runner.run`, then creates a new kernel thread
-- to execute the runtime. The thread is named based on the script's filename.
-- The spawned script is expected to return a function, which will then be executed in the new thread.
-- @tparam string script path or name of the Lua script to spawn.
-- @treturn userdata kernel thread object.
-- @raise error if the script is already running or `percpu` is set.
function runner.spawn(script, context, percpu, ...)
	if percpu then
		error("spawn does not support percpu scripts")
	end
	local runtime = runner.run(script, context, percpu, ...)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	env.threads[script] = t
	return t
end

local function stop_percpu(script)
	if not env.percpu[script] then
		return
	end
	for cpu = 0, linux.numcpus() - 1 do
		stop(env.runtimes, key(script, cpu))
	end
	env.percpu[script] = nil
end

--- Stops a running script and its associated thread, if any.
-- It attempts to stop the thread first, then the runtime.
-- @tparam string script name of the script to stop. The ".lua" extension will be trimmed.
-- @raise error on a single instance of a percpu script; stop it by name.
function runner.stop(script)
	local script = trim(script)
	if ispercpukey(script) then
		error(string.format("%s is a percpu instance; stop the script by name", script))
	end
	stop(env.threads, script)
	stop(env.runtimes, script)
	stop_percpu(script)
end

--- Lists the names of all currently running scripts.
-- Iterates over the `env.percpu` and `env.runtimes` RCU tables to collect
-- script names; a percpu script is named once, not once per CPU id.
-- @treturn string A comma-separated string of running script names, or an empty string if no scripts are running.
function runner.list()
	local list = {}
	rcu.map(env.percpu, function (script)
		table.insert(list, script)
	end)
	rcu.map(env.runtimes, function (script)
		if not ispercpukey(script) then
			table.insert(list, script)
		end
	end)
	return table.concat(list, ', ')
end

local function stopall(registry)
	rcu.map(registry, function (script)
		runner.stop(script)
	end)
end

--- Shuts down all running scripts and their threads.
-- Iterates over `env.percpu` and `env.runtimes` and calls `runner.stop` for each script.
function runner.shutdown()
	stopall(env.percpu)
	stopall(env.runtimes)
end

--- Initializes the runner's internal state.
-- Creates RCU-safe tables for storing runtimes and threads.
-- This is typically called during Lunatik's initialization.
function runner.startup()
	env.runtimes = env.runtimes or rcu.table()
	env.percpu = env.percpu or rcu.table()
	env.threads = env.threads or rcu.table()
end

return runner

