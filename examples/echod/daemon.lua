--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
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
			local runtime = lunatik.runtime("examples/" .. worker)
			runtime:resume(control, session)
			thread.run(runtime, worker .. n)
			n = n + 1
		elseif session == errno.AGAIN then
			linux.schedule(100)
		end
	end
	control:setbyte(1, 0) -- dead
	print("echod [daemon]: stopped")
end

return daemon

