--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket connect test (see connect.sh).

local socket = require("socket")
local inet   = require("socket.inet")
local unix   = require("socket.unix")
local net    = require("net")
local sk     = require("linux.socket")

local format = string.format

local LOOPBACK <const> = net.aton("127.0.0.1")
local NONBLOCK <const> = sk.sock.NONBLOCK
-- a port whose value carries the O_NONBLOCK bit a connect flag is read for
local PORT     <const> = 6922
local PATH     <const> = "/tmp/lunatikconnect.sock"
local BACKLOG  <const> = 4

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, 0)
end

local function say(what)
	print("socket connect: " .. what)
end

local server = tcpsocket()
server:bind(LOOPBACK, PORT)
server:listen(BACKLOG)

local client = tcpsocket()
local connected, err = client:connect(LOOPBACK, PORT)
assert(connected == true, format("a connect with no flags answered %s, %s", connected, err))
say("an address and a port alone connect")
client:close()

local nonblocking = tcpsocket()
connected, err = nonblocking:connect(LOOPBACK, PORT, NONBLOCK)
assert(connected == nil and err == "EINPROGRESS", format("a non-blocking connect answered %s, %s", connected, err))
say("a flag past the port reaches the kernel")
nonblocking:close()

local wrapped = inet.tcp()
connected, err = wrapped:connect(inet.localhost, PORT, NONBLOCK)
assert(connected == nil and err == "EINPROGRESS", format("inet:connect answered %s, %s", connected, err))
say("inet:connect hands the answer through")
wrapped:close()
server:close()

local refused = tcpsocket()
local ok, refusal = pcall(refused.connect, refused, LOOPBACK, PORT)
assert(not ok and refusal == "ECONNREFUSED", format("a connect to a closed port answered %s, %s", ok, refusal))
say("a refused connect raises")
refused:close()

local listener = unix.stream(PATH)
listener:bind()
listener:listen(BACKLOG)

local peer = unix.stream(PATH)
connected, err = peer:connect()
assert(connected == true, format("a connect to a path answered %s, %s", connected, err))
say("a path alone connects")
peer:close()
listener:close()

