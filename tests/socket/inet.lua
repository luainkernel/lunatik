--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket inet test (see inet.sh).

local inet = require("socket.inet")

local BACKLOG <const> = 1

local server = inet.tcp()
server:bind(inet.localhost, 0)
server:listen(BACKLOG)
local host, port = server:getsockname()

local client = inet.tcp()
client:connect(inet.localhost, port)
local session = server:accept()
local peerhost, peerport = client:getpeername()

session:close()
client:close()
server:close()

assert(host == inet.localhost and port ~= 0, "unexpected local address: " .. host .. ":" .. port)
print("socket inet: getsockname ok")
assert(peerhost == inet.localhost and peerport == port, "unexpected peer: " .. peerhost .. ":" .. peerport)
print("socket inet: getpeername ok")

