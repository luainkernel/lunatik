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

local lunatik = require("lunatik")
local thread  = require("thread")
local socket  = require("socket")
local inet    = require("socket.inet")
local linux   = require("linux")
local data    = require("data")

local shouldstop = thread.shouldstop
local task = linux.task
local sock = socket.sock
local errno = linux.errno

local control = data.new(2)
control:setbyte(1, 1) -- alive

local server = inet.tcp()
server:bind(inet.localhost, 1337)
server:listen()

local n = 1 
local worker = "echod/worker"

local function daemon()
	print("echod [daemon]: started")
	while (not shouldstop()) do
		local ok, session = pcall(server.accept, server, sock.NONBLOCK)
		if ok then
			control:setbyte(0, n) -- #workers
			thread.run(lunatik.runtime("examples/" .. worker), worker .. n, control, session)
			n = n + 1 
		elseif session == errno.AGAIN then
			linux.schedule(100, task.INTERRUPTIBLE)
		end
	end
	control:setbyte(1, 0) -- dead
	print("echod [daemon]: stopped")
end

return daemon

