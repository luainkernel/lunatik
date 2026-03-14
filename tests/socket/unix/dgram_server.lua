--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- DGRAM server for the socket.unix DGRAM test (see dgram.sh).
-- Binds using the path stored at construction, receives one datagram via a
-- DONTWAIT loop, asserts the expected message.

local unix   = require("socket.unix")
local socket = require("socket")
local thread = require("thread")
local linux  = require("linux")

local DONTWAIT = socket.msg.DONTWAIT
local PATH     = "/tmp/lunatik_unix_dgram.sock"

local server = unix.dgram(PATH)
server:bind()

return function()
	while not thread.shouldstop() do
		local ok, msg = pcall(server.receivefrom, server, 64, DONTWAIT)
		if ok then
			assert(msg == "hello dgram", "expected 'hello dgram', got: " .. tostring(msg))
			server:close()
			print("unix dgram: server ok")
			while not thread.shouldstop() do
				linux.schedule(10)
			end
			return
		elseif msg == "EAGAIN" then
			linux.schedule(10)
		else
			error(msg)
		end
	end
	server:close()
end

