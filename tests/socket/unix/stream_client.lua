--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- STREAM client for the socket.unix STREAM test (see stream.sh).
-- Connects using the path stored at construction (no explicit path to connect()),
-- sends "ping", asserts "pong" reply.

local unix = require("socket.unix")
local struct = require("struct")
local sk = require("linux.socket")

local TIMEOUT <const> = 2

local timeval = struct(sk.layout.timeval)

local PATH   = "/tmp/lunatik_unix_stream.sock"
local client = unix.stream(PATH)
-- a server that never answers fails the case instead of parking the client in its receive
client.socket:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(TIMEOUT, 0))

client:connect()         -- uses stored PATH
client:send("ping")

local reply = client:receive(64)
assert(reply == "pong", "expected 'pong', got: " .. tostring(reply))

client:close()
print("unix stream: client ok")

