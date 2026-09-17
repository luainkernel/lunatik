--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the handshake upcall test (see upcall.sh).

local socket    = require("socket")
local net       = require("net")
local handshake = require("handshake")
local sk        = require("linux.socket")

local LOCALHOST <const> = "127.0.0.1"

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

local lone = tcpsocket()
local ok, err = pcall(handshake.client, lone)
assert(not ok and err == "ENOTCONN", "an unconnected socket should raise ENOTCONN, got " .. tostring(err))
print("handshake upcall: an unconnected socket is refused")
lone:close()

local server = tcpsocket()
server:bind(net.aton(LOCALHOST), 0)
server:listen()
local _, port = server:getsockname()

local client = tcpsocket()
client:connect(net.aton(LOCALHOST), port)

-- handshake_req_submit answers EINVAL for a socket carrying no struct file and
-- ESRCH only past that test, so the errno is the reading that the file is there
ok, err = pcall(handshake.client, client)
assert(not ok and err == "ESRCH", "a client hello should raise ESRCH, got " .. tostring(err))
print("handshake upcall: a client hello reaches submit and finds no agent")

ok, err = pcall(handshake.client, client)
assert(not ok and err == "ESRCH", "a second client hello should raise ESRCH, got " .. tostring(err))
print("handshake upcall: a second hello on the same socket reaches submit")

ok, err = pcall(handshake.server, client, {cert = 1, privkey = 1})
assert(not ok and err == "ESRCH", "a server hello should raise ESRCH, got " .. tostring(err))
print("handshake upcall: a server x509 hello reaches submit")

-- the accepted end of the identity bound, and the only case that runs the copy
-- loop to a submit: tls_client_hello_psk takes 1 to 5 and refuses the rest
ok, err = pcall(handshake.client, client, {peerids = {1, 2, 3, 4, 5}})
assert(not ok and err == "ESRCH", "five identities should raise ESRCH, got " .. tostring(err))
print("handshake upcall: five identities reach submit")

-- the two arms no other case selects, which complete the five the bindings offer
ok, err = pcall(handshake.client, client, {cert = 1, privkey = 1})
assert(not ok and err == "ESRCH", "a client x509 hello should raise ESRCH, got " .. tostring(err))
print("handshake upcall: a client x509 hello reaches submit")

ok, err = pcall(handshake.server, client, {peerids = {1}})
assert(not ok and err == "ESRCH", "a server psk hello should raise ESRCH, got " .. tostring(err))
print("handshake upcall: a server psk hello reaches submit")

client:close()
server:close()

