--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side listener for the tls_connect example test (see
-- example_connect.sh): it holds the port the example dials, so the example's
-- connect succeeds and the hello is what the run stops at.

local socket = require("socket")
local net    = require("net")
local sk     = require("linux.socket")

-- the address and port examples/tls_connect.lua connects to
local LOCALHOST <const> = "127.0.0.1"
local PORT      <const> = 4433

-- global, so the listener outlives the chunk and the shell closes it by
-- stopping this runtime
listener = socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
listener:setsockopt(sk.sol.SOCKET, sk.so.REUSEADDR, 1)
listener:bind(net.aton(LOCALHOST), PORT)
listener:listen()

