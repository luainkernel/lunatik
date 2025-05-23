--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
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

