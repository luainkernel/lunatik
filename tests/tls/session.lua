--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A keyed kTLS loopback pair for the tls test scripts: the kernel selftest's
-- trick of giving both ends the same key material on both directions, so each
-- side's TX matches the other's RX and no handshake is needed.

local socket = require("socket")
local net    = require("net")
local tls    = require("tls")
local sk     = require("linux.socket")
local ltls   = require("linux.tls")

local rep = string.rep

local LOCALHOST <const> = "127.0.0.1"
local ULPNAME   <const> = "tls"

local names = {}
for name, cipher in pairs(ltls.cipher) do names[cipher] = name end

local session = {}

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

-- fixed vectors of exactly the sizes the cipher wants
local function payload(version, cipher)
	local name = names[cipher]
	local saltsize = ltls.size[name .. "_SALT_SIZE"]
	-- nil rather than "" where the cipher has no salt, as a script would write it
	local salt = saltsize > 0 and rep("\3", saltsize) or nil
	return tls.pack(version, cipher, rep("\1", ltls.size[name .. "_IV_SIZE"]),
		rep("\2", ltls.size[name .. "_KEY_SIZE"]), salt, rep("\4", ltls.size[name .. "_REC_SEQ_SIZE"]))
end

-- both ends of a connection over a listener bound to port 0, so a test takes no
-- fixed port from the host
function session.connectpair()
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

-- one session on both directions of one end; raises what the kernel refused
-- with, a cipher whose AEAD it does not build included
function session.key(sock, version, cipher)
	local blob = payload(version, cipher)
	sock:setsockopt(sk.sol.TCP, sk.tcp.ULP, ULPNAME)
	sock:setsockopt(sk.sol.TLS, ltls.TX, blob)
	sock:setsockopt(sk.sol.TLS, ltls.RX, blob)
end

-- the same session on both ends, so each side's TX matches the other's RX
function session.install(client, server, version, cipher)
	session.key(client, version, cipher)
	session.key(server, version, cipher)
end

function session.closepair(client, server)
	client:close()
	server:close()
end

return session

