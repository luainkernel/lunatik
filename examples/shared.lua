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

local thread = require("thread")
local socket = require("socket")
local inet   = require("socket.inet")
local rcu    = require("rcu")
local data   = require("data")
local linux  = require("linux")

local shared = rcu.table()

local server = inet.tcp()
server:bind(inet.localhost, 90)
server:listen()

local shouldstop = thread.shouldstop
local task = linux.task
local sock = socket.sock
local errno = linux.errno

local size = 1024

local function handle(session)
	repeat
		local request = session:receive(size)
		local key, assign, value = string.match(request, "(%w+)(=*)(%w*)\n")
		if key then
			if assign ~= "" then
				local slot
				if value ~= "" then
					slot = shared[key] or data.new(size)
					slot:setstring(0, value)
				end

				shared[key] = slot
			else
				local value = shared[key]:getstring(0, size)
				session:send(value .. "\n")
			end
		end
	until (not key or shouldstop())
end

local function daemon()
	print("starting shared...")
	while (not shouldstop()) do
		local ok, session = pcall(server.accept, server, sock.NONBLOCK)
		if ok then
			handle(session)
		elseif session == errno.AGAIN then
			linux.schedule(100)
		end
	end
	print("stopping shared...")
end

return daemon

