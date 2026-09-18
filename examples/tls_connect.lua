--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local tls    = require("socket.tls")
local struct = require("struct")
local sk     = require("linux.socket")

local timeval = struct(sk.layout.timeval)

local ADDRESS  <const> = "127.0.0.1"
local PORT     <const> = 4433
local PEERNAME <const> = "localhost"
local REQUEST  <const> = "GET / HTTP/1.0\r\n\r\n"
local READMAX  <const> = 4096

local HANDSHAKE <const> = 5000
-- seconds, not the milliseconds above: SO_RCVTIMEO refuses a tv_usec of a second or more
local REPLY     <const> = 5

local conn <close> = tls.connect(ADDRESS, PORT, {peername = PEERNAME, timeout = HANDSHAKE})

-- the script body holds the device for as long as it runs, so the reply is
-- waited for with a bound rather than until the server feels like answering
conn:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(REPLY, 0))
conn:send(REQUEST)

local reply = conn:receive(READMAX)
print("tls_connect: " .. #reply .. " bytes of plaintext: " .. reply:match("^[^\r\n]*"))

