--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The loopback topology the tunnel tests are built on: one listener the relay
-- accepts both its ends from, the far ends a peer script holds, and the
-- payloads the shell greps for.

local socket = require("socket")
local net    = require("net")
local struct = require("struct")
local thread = require("thread")
local linux  = require("linux")
local sk     = require("linux.socket")

local insert = table.insert

local timeval = struct(sk.layout.timeval)

local LOCALHOST <const> = "127.0.0.1"
local ENDS      <const> = 2
-- seconds: SO_RCVTIMEO refuses a tv_usec of a second or more
local BOUND     <const> = 2
-- milliseconds between two attempts at a connection that has not arrived
local POLL      <const> = 10
local EAGAIN    <const> = "EAGAIN"

local pair = {}

-- above the ports tests/socket and tests/skb bind
pair.port = 6924
-- wider than any payload here, so a read is cut short only where a case means it
pair.readmax = 64
pair.atob = "alpha to bravo"
pair.btoa = "bravo to alpha"
-- what inspect.lua's transform drops rather than forwards
pair.dropped = "drop me"

-- every call a peer makes is bounded, so a relay that moves nothing fails the
-- test instead of leaving the device wedged
function pair.tcp()
	local sock = socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
	sock:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(BOUND, 0))
	sock:setsockopt(sk.sol.SOCKET, sk.so.SNDTIMEO_NEW, timeval:pack(BOUND, 0))
	return sock
end

function pair.listener()
	local listener = pair.tcp()
	-- the previous case's accepted connections still hold the port in TIME_WAIT
	listener:setsockopt(sk.sol.SOCKET, sk.so.REUSEADDR, 1)
	listener:bind(net.aton(LOCALHOST), pair.port)
	listener:listen()
	return listener
end

-- both far ends, in the order the relay accepts them; a caller that has to set
-- an option before the connection exists passes its own socket
function pair.connectpair(a, b)
	a, b = a or pair.tcp(), b or pair.tcp()
	a:connect(net.aton(LOCALHOST), pair.port)
	b:connect(net.aton(LOCALHOST), pair.port)
	return a, b
end

-- the relay's own two ends, accepted without blocking so the thread stays
-- stoppable while it waits for them; nil where it was stopped first
function pair.accept(listener)
	local ends = {}
	while #ends < ENDS do
		if thread.shouldstop() then
			return nil
		end
		local ok, sock = pcall(listener.accept, listener, sk.sock.NONBLOCK)
		if ok then
			insert(ends, sock)
		elseif sock == EAGAIN then
			linux.schedule(POLL)
		else
			error(sock, 0)
		end
	end
	return ends[1], ends[2]
end

-- one payload through the relay and out the far side, both calls bounded
function pair.through(from, to, payload)
	from:send(payload)
	return to:receiverecord(pair.readmax)
end

return pair

