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

local sk   = require("linux.socket")
local af   = sk.af
local sock = sk.sock

local raw = {}

---
-- Creates a raw packet socket bound to an EtherType and an interface.
-- It receives the frames of that EtherType, and sends a frame, which starts at the Ethernet
-- header, with `socket:send(frame, proto, ifindex)`, the EtherType in host byte order.
-- @param proto (number) EtherType (defaults to ETH_P_ALL).
-- @param ifindex (number) [optional] Interface index (defaults to listen all interfaces).
-- @return A new raw packet socket bound for proto and ifindex.
-- @raise Error if socket.new() or socket.bind() fail; a socket whose bind fails is closed first,
--   or, from a netdevice callback, which refuses that close, left to the collector, receiving
--   nothing.
-- @usage
--   local rx <close> = raw.new(0x0003)
--   local tx <close> = raw.new(0x88cc, ifindex)
--   tx:send(frame, 0x88cc, ifindex)
-- @see socket.new
-- @see socket.bind
function raw.new(proto, ifindex)
	local proto = proto or eth.ALL
	local ifindex = ifindex or 0
	local s = socket.new(af.PACKET, sock.RAW, 0) -- no frame reaches it until the bind names the ethertype
	local ok, err = pcall(s.bind, s, proto, ifindex)
	if not ok then
		pcall(s.close, s) -- a netdevice callback refuses it: the bind's error is the one to raise
		error(err, 0)
	end
	return s
end

return raw

