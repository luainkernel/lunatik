--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket record test (see record.sh).

local socket = require("socket")
local net    = require("net")
local sk     = require("linux.socket")

local LOCALHOST <const> = "127.0.0.1"
local PAYLOAD   <const> = "plaintext"
-- the TLS content type of application data, which nothing here reads: the
-- socket carries no ULP
local DATA      <const> = 23
-- one past the byte a content type fits in, and one below it
local TOOBIG    <const> = 256
local TOOSMALL  <const> = -1

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

-- both ends of a connection over a listener bound to port 0, so the test takes
-- no fixed port from the host
local function connectpair()
	local listener = tcpsocket()
	listener:bind(net.aton(LOCALHOST), 0)
	listener:listen()
	local _, port = listener:getsockname()
	local client = tcpsocket()
	client:connect(net.aton(LOCALHOST), port)
	local server = listener:accept()
	listener:close()
	return client, server
end

local function closepair(client, server)
	client:close()
	server:close()
end

-- with no tls ULP on the socket, tls_record_content_type never runs, so no
-- control message arrives and the second return is nil
local client, server = connectpair()
client:send(PAYLOAD)
local data, record = server:receiverecord(#PAYLOAD)
closepair(client, server)
assert(data == PAYLOAD, "receiverecord returned " .. tostring(data))
assert(record == nil, "an unkeyed socket should report no record type, got " .. tostring(record))
print("socket record: an unkeyed receive reports no record type")

-- sock_cmsg_send walks the control buffer and skips every level but SOL_SOCKET,
-- so tcp_sendmsg takes the message and ignores the record type
client, server = connectpair()
local sent = client:sendrecord(DATA, PAYLOAD)
local got = server:receive(#PAYLOAD)
closepair(client, server)
assert(sent == #PAYLOAD, "sendrecord sent " .. tostring(sent) .. " of " .. #PAYLOAD)
assert(got == PAYLOAD, "the peer read " .. tostring(got))
print("socket record: an unkeyed send ignores the record type")

-- a content type is one byte, and the bound is what keeps a wider value from
-- being truncated into a different record
client, server = connectpair()
local bigok, bigerr = pcall(client.sendrecord, client, TOOBIG, "x")
local smallok, smallerr = pcall(client.sendrecord, client, TOOSMALL, "x")
closepair(client, server)
assert(not bigok and tostring(bigerr):match("bad argument #2.*out of bounds"),
	"256 should be out of bounds, got " .. tostring(bigerr))
assert(not smallok and tostring(smallerr):match("bad argument #2.*out of bounds"),
	"-1 should be out of bounds, got " .. tostring(smallerr))
print("socket record: a record type outside a byte is refused")

-- the flags argument reaches kernel_recvmsg on the new path too: nothing was
-- sent, so DONTWAIT is the only reason this returns
client, server = connectpair()
local ok, err = pcall(server.receiverecord, server, #PAYLOAD, sk.msg.DONTWAIT)
closepair(client, server)
assert(not ok and err == "EAGAIN", "a non-blocking empty receive should raise EAGAIN, got " .. tostring(err))
print("socket record: a non-blocking receive on an empty socket raises EAGAIN")

