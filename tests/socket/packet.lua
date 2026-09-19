--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the AF_PACKET address test (see packet.sh).

local socket    = require("socket")
local raw       = require("socket.raw")
local linux     = require("linux")
local struct    = require("struct")
local byteorder = require("byteorder")
local sk        = require("linux.socket")
local eth       = require("linux.eth")

local timeval = struct(sk.layout.timeval)

local PROTO      <const> = eth["802_EX1"]
local IFNAME     <const> = "lo"
local PAYLOAD    <const> = "lunatikpacket"
local ETH_HLEN   <const> = 14
local ETH_ALEN   <const> = 6
local MTU        <const> = 1500
local TIMEOUT_MS <const> = 500

local ifindex = linux.ifindex(IFNAME)

local rx <close> = raw.bind(PROTO, ifindex)
rx:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local listening <close> = socket.new(sk.af.PACKET, sk.sock.RAW, byteorder.hton16(PROTO))
listening:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local swapped <close> = socket.new(sk.af.PACKET, sk.sock.RAW, PROTO)
swapped:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local tx <close> = socket.new(sk.af.PACKET, sk.sock.DGRAM, 0)
tx:send(PAYLOAD, PROTO, ifindex)

local frame = rx:receive(MTU)
local reached = listening:receive(MTU)
local missed = not pcall(swapped.receive, swapped, MTU)

assert(#frame >= ETH_HLEN, "short frame: " .. #frame .. " bytes")
print("socket packet: frame carries " .. string.sub(frame, ETH_HLEN + 1))
print("socket packet: destination " .. string.format(string.rep("%02x", ETH_ALEN, ":"),
	string.byte(frame, 1, ETH_ALEN)))
assert(#reached >= ETH_HLEN, "short frame on the unbound socket: " .. #reached .. " bytes")
print("socket packet: network order reaches the unbound socket")
print("socket packet: host order " .. (missed and "misses it" or "reaches it too"))

