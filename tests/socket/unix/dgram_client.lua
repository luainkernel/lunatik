--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- DGRAM client for the socket.unix DGRAM test (see dgram.sh).
-- Creates a socket with the server path stored at construction, then calls
-- sendto() without an explicit path to exercise the stored-path feature.

local unix = require("socket.unix")

local SERVER_PATH = "/tmp/lunatik_unix_dgram.sock"
local client      = unix.dgram(SERVER_PATH)

client:sendto("hello dgram")   -- uses stored SERVER_PATH, no explicit path
client:close()
print("unix dgram: client ok")

