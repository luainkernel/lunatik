--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Client side of the socket.unix abstract address test (see abstract.sh).

local unix = require("socket.unix")

local PEER    <const> = "\0lunatikpeer"
local DGRAM   <const> = "\0lunatikpeerdgram"
local BUFSIZE <const> = 64

local client = unix.stream(PEER)

client:connect()
client:send("ping")

local reply = client:receive(BUFSIZE)
assert(reply == "pong", "expected 'pong', got: " .. tostring(reply))

client:close()

local sender = unix.dgram()
sender:sendto("ping", DGRAM)
sender:close()

print("unix abstract: client ok")

