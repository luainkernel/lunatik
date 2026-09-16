--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket connect test (see connect.sh).

local socket = require("socket")
local unix   = require("socket.unix")
local net    = require("net")
local sk     = require("linux.socket")

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
local ok, err = pcall(client.connect, client, LOOPBACK, PORT)
assert(ok, "a connect with no flags was refused: " .. tostring(err))
say("an address and a port alone connect")
client:close()

local nonblocking = tcpsocket()
ok, err = pcall(nonblocking.connect, nonblocking, LOOPBACK, PORT, NONBLOCK)
assert(not ok and err == "EINPROGRESS", "a non-blocking connect answered: " .. tostring(err))
say("a flag past the port reaches the kernel")
nonblocking:close()
server:close()

local listener = unix.stream(PATH)
listener:bind()
listener:listen(BACKLOG)

local peer = unix.stream(PATH)
ok, err = pcall(peer.connect, peer)
assert(ok, "a connect to a path was refused: " .. tostring(err))
say("a path alone connects")
peer:close()
listener:close()

