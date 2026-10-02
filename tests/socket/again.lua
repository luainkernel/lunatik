--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket again test (see again.sh).

local inet   = require("socket.inet")
local unix   = require("socket.unix")
local struct = require("struct")
local sk     = require("linux.socket")
local test   = require("tests.lib").test

local pack   = table.pack
local format = string.format

local SIZE       <const> = 64
local MESSAGE    <const> = "again"
local ANYPORT    <const> = 0
local TIMEOUT_MS <const> = 100
local DONTWAIT   <const> = sk.msg.DONTWAIT
local NONBLOCK   <const> = sk.sock.NONBLOCK
local RCVTIMEO   <const> = sk.so.RCVTIMEO_NEW
local SNDTIMEO   <const> = sk.so.SNDTIMEO_NEW
local NAME       <const> = "\0lunatikagain"
local BUFSIZE    <const> = 4096
-- more than a stream's send and receive buffers of BUFSIZE take while nobody reads
local FLOOD      <const> = string.rep("x", 1 << 20)
-- more sends than a datagram queue or a send buffer takes while nobody reads
local ATTEMPTS   <const> = 1024
local IP_LOCAL_PORT_RANGE <const> = 51 -- uapi/linux/in.h

local timeval = struct(sk.layout.timeval)

local function bounded(sock, option)
	sock.socket:setsockopt(sk.sol.SOCKET, option, timeval:pack(0, TIMEOUT_MS * 1000))
	return sock
end

local function bound(class)
	local sock = bounded(class(), RCVTIMEO)
	sock:bind(inet.localhost, ANYPORT)
	return sock
end

local function again(what, ...)
	local answer = pack(...)
	assert(answer[1] == nil and answer[2] == "EAGAIN" and answer[3] == nil, format("%s answered %s, %s, %s",
		what, tostring(answer[1]), tostring(answer[2]), tostring(answer[3])))
end

local function raises(what, expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok and err == expected, format("%s answered %s, %s", what, tostring(ok), tostring(err)))
end

local function fill(what, send, ...)
	for _ = 1, ATTEMPTS do
		local sent, extra = send(...)
		if sent == false then
			assert(extra == nil, format("%s answered false and %s", what, tostring(extra)))
			return
		end
		assert(type(sent) == "number", format("%s answered %s", what, tostring(sent)))
	end
	error(what .. " never answered false")
end

test("socket:receive answers nil and EAGAIN when the wait finds nothing to read", function()
	local udp = bound(inet.udp)
	again("a nonblocking receive", udp:receive(SIZE, DONTWAIT))
	again("a nonblocking socket:receivefrom", udp.socket:receivefrom(SIZE, DONTWAIT))
	again("a timed receive", udp:receive(SIZE))
	again("a nonblocking inet.udp:receivefrom", udp:receivefrom(SIZE, DONTWAIT))
	udp:close()
end)

test("socket:receive answers the message the wait finds", function()
	local udp = bound(inet.udp)
	local addr, port = udp:getsockname()
	udp:send(MESSAGE, addr, port)
	local message = udp:receive(SIZE)
	assert(message == MESSAGE, "a timed receive answered " .. tostring(message))
	udp:send(MESSAGE, addr, port)
	local sender
	message, sender = udp:receivefrom(SIZE)
	assert(message == MESSAGE and sender == addr, "receivefrom answered " .. tostring(message))
	udp:close()
end)

test("socket:accept answers nil and EAGAIN when the wait finds no connection", function()
	local listener = bound(inet.tcp)
	listener:listen()
	again("a nonblocking accept", listener:accept(NONBLOCK))
	again("a timed accept", listener:accept())
	listener:close()
end)

test("socket:accept answers the connection the wait finds", function()
	local listener = bound(inet.tcp)
	listener:listen()
	local client = inet.tcp()
	client:connect(listener:getsockname())
	local session = listener:accept()
	assert(session ~= nil, "a timed accept missed a pending connection")
	session:close()
	client:close()
	listener:close()
end)

test("socket:receive, socket:accept and socket:send raise a failure other than EAGAIN", function()
	local listener = bound(inet.tcp)
	listener:listen()
	raises("a receive on a listener", "ENOTCONN", listener.receive, listener, SIZE, DONTWAIT)
	local idle = inet.tcp()
	raises("an accept on a socket that does not listen", "EINVAL", idle.accept, idle, NONBLOCK)
	idle:close()
	listener:close()
	local udp = bounded(inet.udp(), SNDTIMEO)
	raises("a send with no destination", "EDESTADDRREQ", udp.send, udp, MESSAGE)
	udp:close()
end)

test("socket:connect raises the EAGAIN of an implicit bind that finds no free port", function()
	local holder = bound(inet.udp)
	local _, port = holder:getsockname()
	local udp = inet.udp()
	udp.socket:setsockopt(sk.sol.IP, IP_LOCAL_PORT_RANGE, port << 16 | port)
	raises("a connect with no free port to bind", "EAGAIN", udp.connect, udp, inet.localhost, port)
	udp:close()
	holder:close()
end)

test("socket:send answers false when a send timeout ends the wait with nothing queued", function()
	local receiver = unix.dgram(NAME)
	receiver:bind()
	local sender = bounded(unix.dgram(NAME), SNDTIMEO)
	local sent = sender:sendto(MESSAGE)
	assert(sent == #MESSAGE, "a datagram send with room answered " .. tostring(sent))
	fill("a datagram send to a full queue", sender.sendto, sender, MESSAGE)
	sender:close()
	receiver:close()
end)

test("socket:send on a stream answers the bytes queued before its send timeout, and false once none fit", function()
	local listener = bound(inet.tcp)
	listener.socket:setsockopt(sk.sol.SOCKET, sk.so.RCVBUF, BUFSIZE)
	listener:listen()
	local client = bounded(inet.tcp(), SNDTIMEO)
	client.socket:setsockopt(sk.sol.SOCKET, sk.so.SNDBUF, BUFSIZE)
	client:connect(listener:getsockname())
	local session = listener:accept()
	local sent = client:send(FLOOD)
	assert(type(sent) == "number" and sent > 0 and sent < #FLOOD, "a stream send answered " .. tostring(sent))
	fill("a stream send to a full buffer", client.send, client, MESSAGE)
	session:close()
	client:close()
	listener:close()
end)

