--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
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
-- @tparam string script The script filename (e.g., "myscript.lua").
-- @treturn string The script name without the ".lua" extension (e.g., "myscript").
local function trim(script) -- drop ".lua" file extension
	return script:gsub("(%w+).lua", "%1")
end

--- Runs a Lunatik script in the current context.
-- Creates a new Lunatik runtime for the given script and registers it.
-- Throws an error if a script with the same name is already running.
-- @tparam string script The path or name of the Lua script to run. The ".lua" extension will be trimmed.
-- @param ... Additional arguments to pass to the script's main function.
-- @treturn table The created Lunatik runtime object.
-- @raise error if the script is already running.
function runner.run(script, ...)
	local script = trim(script)
	if env.runtimes[script] then
		error(string.format("%s is already running", script))
	end
	local runtime = lunatik.runtime(script, ...)
	env.runtimes[script] = runtime
	return runtime
end

--- Spawns a Lunatik script in a new kernel thread.
-- First, it runs the script using `runner.run`, then creates a new kernel thread
-- to execute the runtime. The thread is named based on the script's filename.
-- The spawned script is expected to return a function, which will then be executed in the new thread.
-- @tparam string script The path or name of the Lua script to spawn.
-- @param ... Additional arguments to pass to the script's main function.
-- @treturn userdata The kernel thread object.
function runner.spawn(script, ...)
	local runtime = runner.run(script, ...)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	env.threads[script] = t
	return t
end

--- Stops an item (runtime or thread) in the given registry.
-- If the item exists in the registry, its `stop()` method is called,
-- and it's removed from the registry.
-- @local
-- @function stop
-- @tparam table registry The registry table (e.g., `env.threads` or `env.runtimes`).
-- @tparam string script The key (script name) of the item to stop.
local function stop(registry, script)
	if registry[script] then
		registry[script]:stop()
		registry[script] = nil
	end
end

--- Stops a running script and its associated thread, if any.
-- It attempts to stop the thread first, then the runtime.
-- @tparam string script The name of the script to stop. The ".lua" extension will be trimmed.
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
	-- The original code `table.concat(list, ', ')` correctly returns an empty string
	-- if `list` is empty, so no change to the code logic is needed or made here.
	return table.concat(list, ', ')
end

--- Shuts down all running scripts and their threads.
-- Iterates over `env.runtimes` and calls `runner.stop` for each script.
function runner.shutdown()
	rcu.map(env.runtimes, function (script)
		runner.stop(script)
	end)
end

--- Initializes the runner's internal state.
-- Creates RCU-safe tables for storing runtimes and threads.
-- This is typically called during Lunatik's initialization.
function runner.startup()
	env.runtimes = rcu.table()
	env.threads = rcu.table()
end

return runner

