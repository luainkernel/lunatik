--
-- SPDX-FileCopyrightText: (c) 2025 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
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

local af   = socket.af
local sock = socket.sock

local ETH_P_ALL  = 0x0003

local raw = {}

---
-- Creates and binds a raw packet socket for receiving and sending frames.
-- @param proto (number) EtherType (defaults to ETH_P_ALL).
-- @param ifindex (number) Interface index.
-- @return A new raw packet socket bound for RX.
-- @raise Error if socket.new() or socket.bind() fail.
-- @see socket.new
-- @see socket.bind
function raw.new(proto, ifindex)
	local proto = proto or ETH_P_ALL
	local ifindex = ifindex or 0
	local s = socket.new(af.PACKET, sock.RAW, proto)
	s:bind(string.pack(">H", proto), ifindex)
	return s
end

return raw

