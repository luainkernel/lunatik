--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- STREAM client for the socket.unix STREAM test (see stream.sh).
-- Connects using the path stored at construction (no explicit path to connect()),
-- sends "ping", asserts "pong" reply.

local unix = require("socket.unix")

local PATH   = "/tmp/lunatik_unix_stream.sock"
local client = unix.stream(PATH)

client:connect()         -- uses stored PATH
client:send("ping")

local reply = client:receive(64)
assert(reply == "pong", "expected 'pong', got: " .. tostring(reply))

client:close()
print("unix stream: client ok")

