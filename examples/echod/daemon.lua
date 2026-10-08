--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local thread  = require("thread")
local inet    = require("socket.inet")
local linux   = require("linux")
local data    = require("data")

local shouldstop = thread.shouldstop
local sock = require("linux.socket").sock

local workers = {}

local server = inet.tcp()
server:bind(inet.localhost, 1337)
server:listen()

local n = 1
local worker = "echod/worker"

local function reap()
	for t, done in pairs(workers) do
		if done:getbyte(0) ~= 0 then
			t:stop()
			workers[t] = nil
		end
	end
end

local function daemon()
	print("echod [daemon]: started")
	while (not shouldstop()) do
		local session = server:accept(sock.NONBLOCK)
		if session then
			local number = data.new(8)
			number:setint64(0, n)
			local runtime = lunatik.runtime("examples/" .. worker)
			local done = data.new(1)
			workers[thread.run(runtime, worker .. n, number, session, done)] = done
			n = n + 1
		else
			linux.schedule(100)
		end
		reap()
	end
	print("echod [daemon]: stopped")
end

return daemon

