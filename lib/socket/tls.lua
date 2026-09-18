--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- TLS client sockets. Connects a TCP socket and has the `tlshd` agent
-- negotiate a session on it, so what comes back is a socket already keyed for
-- kTLS: reads and writes on it carry plaintext. The agent attaches the `tls`
-- ULP and installs the keys itself, so nothing here does, and the content type
-- a record on it arrives in is one `tls.record` names.
--
-- @module socket.tls
-- @see socket
-- @see handshake
-- @see tls
--
local socket    = require("socket")
local net       = require("net")
local handshake = require("handshake")

local sk = require("linux.socket")

local tls = {}

---
-- Connects to a TLS server and hands back the socket the agent keyed.
-- Blocks for the whole handshake, so it needs a sleepable runtime.
-- @param address (string) the server's IPv4 address, e.g. "192.0.2.1".
-- @param port (number) the server's TCP port.
-- @param opts (table) [optional] handshake options, as `handshake.client` takes them.
-- @return A connected socket carrying the session.
-- @raise Error if the connection or the handshake fails.
-- @usage
--   local conn <close> = tls.connect("192.0.2.1", 443, {peername = "example.com"})
--   conn:send("GET / HTTP/1.0\r\n\r\n")
-- @see socket.connect
-- @see handshake.client
function tls.connect(address, port, opts)
	local conn = socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
	conn:connect(net.aton(address), port)
	handshake.client(conn, opts)
	return conn
end

return tls

