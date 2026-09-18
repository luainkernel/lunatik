--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A connection the tlstunnel example cannot serve (see example_tunnel.sh):
-- plaintext straight at the upstream's port, where a TLS record is what the
-- keyed leg reads.

local net    = require("net")
local linux  = require("linux")
local common = require("examples.tlstunnel.common")

local PLAINTEXT <const> = "no record header in front of this\r\n\r\n"
-- milliseconds the connection is held open: the upstream polls its accept and
-- its read every 10 ms, and the record layer has to look at these bytes
local HOLD      <const> = 100

-- the port and the address are the example's own, so a port it moves moves here too
local conn <close> = common.tcp()
conn:connect(net.aton(common.address), common.upstreamport)
conn:send(PLAINTEXT)
linux.schedule(HOLD)

