--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- DGRAM server for the socket.unix DGRAM test (see dgram.sh).
-- Binds using the path stored at construction, receives one datagram via a
-- DONTWAIT loop, asserts the expected message.

local unix   = require("socket.unix")
local thread = require("thread")
local linux  = require("linux")

local DONTWAIT = require("linux.socket").msg.DONTWAIT
local PATH     = "/tmp/lunatik_unix_dgram.sock"

local server = unix.dgram(PATH)
server:bind()

return function()
	while not thread.shouldstop() do
		local msg = server:receivefrom(64, DONTWAIT)
		if msg then
			assert(msg == "hello dgram", "expected 'hello dgram', got: " .. tostring(msg))
			server:close()
			print("unix dgram: server ok")
			while not thread.shouldstop() do
				linux.schedule(10)
			end
			return
		else
			linux.schedule(10)
		end
	end
	server:close()
end

