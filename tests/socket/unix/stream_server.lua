--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- STREAM server for the socket.unix STREAM test (see stream.sh).
-- Binds and listens using the path stored at construction, accepts one
-- connection via a NONBLOCK loop, receives "ping" via a DONTWAIT loop,
-- replies "pong".

local unix   = require("socket.unix")
local socket = require("socket")
local thread = require("thread")
local linux  = require("linux")

local sk       = require("linux.socket")
local NONBLOCK = sk.sock.NONBLOCK
local DONTWAIT = sk.msg.DONTWAIT
local PATH     = "/tmp/lunatik_unix_stream.sock"

local server = unix.stream(PATH)
server:bind()
server:listen(1)

local function receive(session)
	while not thread.shouldstop() do
		local ok, msg = pcall(session.receive, session, 64, DONTWAIT)
		if ok then
			return msg
		elseif msg == "EAGAIN" then
			linux.schedule(10)
		else
			error(msg)
		end
	end
end

return function()
	while not thread.shouldstop() do
		local ok, session = pcall(server.accept, server, NONBLOCK)
		if ok then
			local msg = receive(session)
			if not msg then
				break
			end
			assert(msg == "ping", "expected 'ping', got: " .. tostring(msg))
			session:send("pong")
			session:close()
			server:close()
			print("unix stream: server ok")
			while not thread.shouldstop() do
				linux.schedule(10)
			end
			return
		elseif session == "EAGAIN" then
			linux.schedule(10)
		else
			error(session)
		end
	end
	server:close()
end

