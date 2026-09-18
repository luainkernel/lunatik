--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- What the two halves of the tlstunnel example share: the loopback ports they
-- meet on, the listener and the accept both of them run, and the fixed key
-- material the kTLS leg between them is keyed with.

local socket = require("socket")
local net    = require("net")
local tls    = require("tls")
local thread = require("thread")
local linux  = require("linux")
local sk     = require("linux.socket")
local ltls   = require("linux.tls")

local rep = string.rep

local ULPNAME <const> = "tls"
local CIPHER  <const> = "AES_GCM_128"
-- milliseconds an accept that found nothing yields before it polls again
local POLL    <const> = 10
local EAGAIN  <const> = "EAGAIN"

local common = {}

common.address = "127.0.0.1"
-- where a client meets the tunnel, and where the tunnel meets the upstream,
-- above the ports the tests bind
common.plainport = 6926
common.upstreamport = 6927

-- the same blob on both directions of both ends, so each side's transmit key is
-- the other's receive key: the kernel selftest's trick, and the whole reason
-- this example needs neither a handshake nor tlshd. Demonstration vectors, not
-- a session.
local blob = tls.pack(tls.version.TLS_1_3, ltls.cipher[CIPHER], rep("\1", ltls.size[CIPHER .. "_IV_SIZE"]),
	rep("\2", ltls.size[CIPHER .. "_KEY_SIZE"]), rep("\3", ltls.size[CIPHER .. "_SALT_SIZE"]),
	rep("\4", ltls.size[CIPHER .. "_REC_SEQ_SIZE"]))

function common.tcp()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

function common.listener(port)
	local listener = common.tcp()
	-- the previous run's accepted connections still hold the port in TIME_WAIT
	listener:setsockopt(sk.sol.SOCKET, sk.so.REUSEADDR, 1)
	listener:bind(net.aton(common.address), port)
	listener:listen()
	return listener
end

-- one connection, accepted without blocking so the thread stays stoppable while
-- it waits for one; nil where the thread was stopped instead
function common.accept(listener)
	while not thread.shouldstop() do
		local ok, sock = pcall(listener.accept, listener, sk.sock.NONBLOCK)
		if ok then
			return sock
		end
		if sock ~= EAGAIN then
			error(sock, 0)
		end
		linux.schedule(POLL)
	end
end

function common.key(sock)
	sock:setsockopt(sk.sol.TCP, sk.tcp.ULP, ULPNAME)
	sock:setsockopt(sk.sol.TLS, ltls.TX, blob)
	sock:setsockopt(sk.sol.TLS, ltls.RX, blob)
end

return common

