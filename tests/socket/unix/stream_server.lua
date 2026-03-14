--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- STREAM server for the socket.unix STREAM test (see stream.sh).
-- Binds and listens using the path stored at construction, accepts one
-- connection via a NONBLOCK loop, receives "ping", replies "pong".

local unix   = require("socket.unix")
local socket = require("socket")
local thread = require("thread")
local linux  = require("linux")

local NONBLOCK = socket.sock.NONBLOCK
local PATH     = "/tmp/lunatik_unix_stream.sock"

local server = unix.stream(PATH)
server:bind()
server:listen(1)

return function()
	while not thread.shouldstop() do
		local ok, session = pcall(server.accept, server, NONBLOCK)
		if ok then
			local msg = session:receive(64)
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

