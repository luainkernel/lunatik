--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket.tls connect test (see socket_tls.sh).

local socket = require("socket")
local net    = require("net")
local tls    = require("socket.tls")
local sk     = require("linux.socket")

local LOCALHOST <const> = "127.0.0.1"

local server = socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
server:bind(net.aton(LOCALHOST), 0)
server:listen()
local _, port = server:getsockname()

local ok, err = pcall(tls.connect, LOCALHOST, port)
assert(not ok and err == "ESRCH", "connect should reach the upcall, got " .. tostring(err))
print("socket.tls connect: the socket is connected and the hello reaches submit")

server:close()

