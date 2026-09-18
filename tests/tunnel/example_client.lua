--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side client for the tlstunnel example test (see example_tunnel.sh):
-- one request through the example's plain port and the reply back.

local net    = require("net")
local struct = require("struct")
local common = require("examples.tlstunnel.common")
local sk     = require("linux.socket")

local match = string.match

local timeval = struct(sk.layout.timeval)

-- seconds: SO_RCVTIMEO refuses a tv_usec of a second or more
local BOUND   <const> = 2
local READMAX <const> = 4096
local REQUEST <const> = "GET /tunnel HTTP/1.0\r\n\r\n"

-- the ports and the keying are the example's own, so a port it moves moves here too
local conn <close> = common.tcp()
conn:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(BOUND, 0))
conn:connect(net.aton(common.address), common.plainport)
conn:send(REQUEST)

print("tlstunnel client: read " .. match(conn:receive(READMAX), "^[^\r\n]*"))

