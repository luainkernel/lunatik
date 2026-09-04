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
-- @tparam[opt] boolean ispercpu create one runtime per CPU id, dispatched by the CPU a
--   callback fires on; the script runs once per instance and can read its id with
--   `lunatik.cpu()`. The instances share a netfilter hook; constructors whose
--   registration is global refuse to run in an instance.
-- @treturn table created Lunatik runtime object, or the percpu object when `ispercpu` is set.
-- @raise error if the script is already running.
function runner.run(script, context, ispercpu)
	local script = trim(script)
	if env.runtimes[script] then
		error(string.format("%s is already running", script))
	end
	local runtime = ispercpu and lunatik.percpu(script, context) or lunatik.runtime(script, context)
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
function runner.spawn(script, context, ispercpu)
	if ispercpu then
		error("spawn does not support percpu scripts")
	end
	local runtime = runner.run(script, context)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	env.threads[script] = t
	return t
end

--- Stops a running script and its associated thread, if any.
-- It attempts to stop the thread first, then the runtime.
-- @tparam string script name of the script to stop. The ".lua" extension will be trimmed.
function runner.stop(script)
	local script = trim(script)
	stop(env.threads, script)
	stop(env.runtimes, script)
end

--- Lists the names of all currently running scripts.
-- Iterates over the `env.runtimes` RCU table to collect script names.
-- @treturn string A comma-separated string of running script names, or an empty string if no scripts are running.
function runner.list()
	local list = {}
	rcu.map(env.runtimes, function (script)
		table.insert(list, script)
	end)
	return table.concat(list, ', ')
end

--- Shuts down all running scripts and their threads.
-- Stops each script as the iteration reaches it: `runner.stop` removes the
-- entry the callback was given, which is all `rcu.map` allows.
function runner.shutdown()
	rcu.map(env.runtimes, runner.stop)
end

local function restore(name)
	local current = env[name]
	if current == nil then
		return rcu.table()
	end
	if type(current) ~= "userdata" then
		error(string.format("_ENV.%s is not an rcu table; unload and load the modules", name))
	end
	return current
end

--- Initializes the runner's internal state.
-- Creates the RCU-safe tables for runtimes and threads, reusing the ones a
-- previous startup left in `env`. A table left by an
-- incompatible runner is rejected: the modules have to be unloaded and loaded.
-- @raise error if a table in `env` is not an rcu table.
function runner.startup()
	env.runtimes = restore("runtimes")
	env.threads = restore("threads")
end

return runner

