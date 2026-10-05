--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
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
local task = require("linux.task")
local sock = require("linux.socket").sock

local size = 1024

local function handle(session)
	repeat
		local request = session:receive(size)
		local key, assign, value = string.match(request, "(%w+)(=*)(%w*)\n")
		if key then
			if assign ~= "" then
				local slot
				if value ~= "" then
					slot = data.new(#value)
					slot:setstring(0, value)
				end

				shared[key] = slot
			else
				local slot = shared[key]
				local reply = slot and slot:getstring(0) or ""
				session:send(reply .. "\n")
			end
		end
	until (not key or shouldstop())
end

local function daemon()
	print("starting shared...")
	while (not shouldstop()) do
		local session = server:accept(sock.NONBLOCK)
		if session then
			local handled, err = pcall(handle, session)
			if not handled then
				print("shared: " .. err)
			end
			session:close()
		else
			linux.schedule(100)
		end
	end
	print("stopping shared...")
end

return daemon

