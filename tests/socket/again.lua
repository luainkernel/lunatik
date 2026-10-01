--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket again test (see again.sh).

local inet   = require("socket.inet")
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

local timeval = struct(sk.layout.timeval)

local function bounded(sock)
	sock.socket:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
	return sock
end

local function bound(class)
	local sock = bounded(class())
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

test("socket:receive and socket:accept raise a failure other than EAGAIN", function()
	local listener = bound(inet.tcp)
	listener:listen()
	raises("a receive on a listener", "ENOTCONN", listener.receive, listener, SIZE, DONTWAIT)
	local idle = inet.tcp()
	raises("an accept on a socket that does not listen", "EINVAL", idle.accept, idle, NONBLOCK)
	idle:close()
	listener:close()
end)

