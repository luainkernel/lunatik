--- Manages Lunatik scripts execution and lifecycle.
-- @module lunatik.runner

local lunatik = require("lunatik")
local thread  = require("thread")
local rcu     = require("rcu")

local env = lunatik._ENV

local runner = {}

--- Removes ".lua" extension from script filename.
-- @local
-- @function trim
-- @tparam string script Script filename.
-- @treturn string Script name without extension.
local function trim(script) -- drop ".lua" file extension
	return script:gsub("(%w+).lua", "%1")
end

--- Runs a Lunatik script in the current context.
-- @tparam string script Path or name of the Lua script.
-- @tparam[opt] string context Execution context: `"process"` (default) or `"softirq"`.
-- @treturn table Lunatik runtime object.
-- @raise error if script is already running.
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
-- @tparam string script Path or name of the Lua script.
-- @treturn userdata Kernel thread object.
function runner.spawn(script, ...)
	local runtime = runner.run(script, ...)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	env.threads[script] = t
	return t
end

--- Stops an item in the given registry.
-- @local
-- @function stop
-- @tparam table registry Registry table (e.g., `env.threads`).
-- @tparam string script Script name key.
local function stop(registry, script)
	if registry[script] then
		registry[script]:stop()
		registry[script] = nil
	end
end

--- Stops a running script and its thread.
-- @tparam string script Script name.
function runner.stop(script)
	local script = trim(script)
	stop(env.threads, script)
	stop(env.runtimes, script)
end

--- Lists all running scripts.
-- @treturn string Comma-separated script names.
function runner.list()
	local list = {}
	rcu.map(env.runtimes, function (script)
		table.insert(list, script)
	end)
	return table.concat(list, ', ')
end

--- Shuts down all running scripts and threads.
function runner.shutdown()
	rcu.map(env.runtimes, function (script)
		runner.stop(script)
	end)
end

--- Initializes the runner's state.
function runner.startup()
	if env.runtimes then return end
	env.runtimes = rcu.table()
	env.threads = rcu.table()
end

return runner

