--
-- Copyright (c) 2023-2024 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

lunatik = require("lunatik")

local device = require("device")
local thread = require("thread")
local rcu    = require("rcu")

local function nop() end

local driver = {name = "lunatik", open = nop, release = nop}

function driver:read()
	local result = self.result
	self.result = nil
	return result
end

local function result(_, ...)
	return select("#", ...) > 0 and tostring(select(1, ...)) or ''
end

function driver:write(buf)
	local ok, err = load(buf)
	if ok then
		err = result(pcall(ok))
	end
	self.result = err
end

driver.__runtimes = lunatik.runtimes()
driver.__threads = {}

function driver:run(script, ...)
	if self.__runtimes[script] then
		error(string.format("%s is already running", script))
	end
	local runtime = lunatik.runtime(script, ...)
	self.__runtimes[script] = runtime
	return runtime
end

function driver:spawn(script, ...)
	local runtime = self:run(script, ...)
	local name = string.match(script, "(%w*/*%w*)$")
	local t = thread.run(runtime, name)
	self.__threads[script] = t
	return t
end

local function stop(registry, script)
	if registry[script] then
		registry[script]:stop()
		registry[script] = nil
	end
end

function driver:stop(script)
	stop(self.__threads, script)
	stop(self.__runtimes, script)
end

function driver:list()
	local list = {}
	rcu.map(self.__runtimes, function (script)
		table.insert(list, script)
	end)
	return table.concat(list, ', ')
end

function driver:shutdown()
	rcu.map(self.__runtimes, function (script)
		self:stop(script)
	end)
end

device.new(driver)
lunatik.driver = driver

