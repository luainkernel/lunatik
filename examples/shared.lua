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
local inet   = require("socket.inet")
local rcu    = require("rcu")

local shared = rcu.table()
rcu.publish("shared", shared)

local server = inet.tcp()
server:bind(inet.localhost, 90)
server:listen()

local shouldstop = thread.shouldstop

local function handle(session)
	repeat
		local request = session:receive(1024)
		local key, assign, value = string.match(request, "(%w+)(=*)(%w*)\n")
		if key then
			if assign ~= "" then
				shared[key] = value == "" and nil or value
			else
				session:send(tostring(shared[key]) .. "\n")
			end
		end
	until (not key or shouldstop())
end

thread.settask(function ()
	print("starting shared...")
	while (not shouldstop()) do
		local session <close> = server:accept()
		local ok, err = pcall(handle, session)
		if not ok then
			print(err)
		end
		session:send("\n")
	end
	print("stopping shared...")
end)

