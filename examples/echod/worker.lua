--
-- Copyright (c) 2023 ring-0 Ltda.
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

local thread = require("thread")
local socket = require("socket")
local data   = require("data")

local shouldstop = thread.shouldstop

local function info(id, message)
	local prefix = "echod [worker #" .. id .. "]"
	print(string.format("%s: %s", prefix, message))
end

local function alive(control)
	return control:getbyte(1) ~= 0
end

local function echo(session)
	local message = session:receive(1024)
	session:send(message)
	return message == ""
end

local function worker(control, session)
	local id = control:getbyte(0)

	info(id, "started")
	repeat
		local ok, err = pcall(echo, session)
		if not ok then 
			return info(id, "aborted")
		end
	until (not alive(control) or err or shouldstop())
	info(id, "stopped")
end

return worker

