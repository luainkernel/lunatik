--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- RAW AF_PACKET socket operations.
-- This module provides a higher-level abstraction over the `socket` module.
--
-- @module socket.raw
-- @see socket
--
local socket = require("socket")
local eth    = require("linux.eth")

local af   = socket.af
local sock = socket.sock

local raw = {}

---
-- Creates and binds a raw packet socket for receiving frames.
-- @param proto (number) EtherType (defaults to ETH_P_ALL).
-- @param ifindex (number) [optional] Interface index (defaults to listen all interfaces).
-- @return A new raw packet socket bound for proto and ifindex.
-- @raise Error if socket.new() or socket.bind() fail.
-- @usage
--   local rx <close> = raw.bind(0x0003)
--   local tx <close> = raw.bind(0x88cc, ifindex)
-- @see socket.new
-- @see socket.bind
function raw.bind(proto, ifindex)
	local proto = proto or eth.ALL
	local ifindex = ifindex or 0
	local s = socket.new(af.PACKET, sock.RAW, proto)
	s:bind(proto, ifindex)
	return s
end

return raw

