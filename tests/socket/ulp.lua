--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tls ULP test (see ulp.sh).

local socket = require("socket")
local net    = require("net")
local sk     = require("linux.socket")

local LOCALHOST <const> = "127.0.0.1"
local ULPNAME   <const> = "tls"

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

local server = tcpsocket()
server:bind(net.aton(LOCALHOST), 0)
server:listen()
local _, port = server:getsockname()

local client = tcpsocket()

-- tls_init takes only an ESTABLISHED socket, so the attach on the unconnected
-- one names the state it wanted
local ok, err = pcall(client.setsockopt, client, sk.sol.TCP, sk.tcp.ULP, ULPNAME)
assert(not ok and err == "ENOTCONN", "unconnected attach should raise ENOTCONN, got " .. tostring(err))
print("socket ulp: unconnected attach refused")

-- the backlog establishes the client side, so there is nothing to accept
client:connect(net.aton(LOCALHOST), port)
client:setsockopt(sk.sol.TCP, sk.tcp.ULP, ULPNAME)
print("socket ulp: attached to a connected socket")

-- the attached ULP hands a SOL_TCP option back to tcp_setsockopt, which finds
-- the socket already carrying one: the only reading of the attach Lua has
ok, err = pcall(client.setsockopt, client, sk.sol.TCP, sk.tcp.ULP, ULPNAME)
assert(not ok and err == "EEXIST", "second attach should raise EEXIST, got " .. tostring(err))
print("socket ulp: second attach refused")

client:close()
server:close()

