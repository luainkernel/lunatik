--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the GC-under-spinlock regression test (see gc.sh).
--

local socket = require("socket")
local fifo   = require("fifo")
local linux  = require("linux")
local thread = require("thread")
local ls     = require("linux.socket")
local af     = ls.af
local sock   = ls.sock

collectgarbage("generational")
collectgarbage("param", "minormul", 0)

local f = fifo.new(256)

return function()
	while not thread.shouldstop() do
		collectgarbage("stop")
		f:push(string.rep("x", 256))

		for i = 1, 10 do
			socket.new(af.PACKET, sock.RAW, 0)
		end

		collectgarbage("restart")
		f:pop(256)
		linux.schedule(1)
	end
end

