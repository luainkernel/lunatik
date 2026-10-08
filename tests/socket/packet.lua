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
local attempt   = require("tests.socket.attempt")

local timeval = struct(sk.layout.timeval)

local PROTO      <const> = eth["802_EX1"]
local PROTO_MAX  <const> = 0xFFFF
local PROTO_NET  <const> = byteorder.hton16(PROTO)
local IFNAME     <const> = "lo"
local PAYLOAD    <const> = "lunatikpacket"
local ETH_HLEN   <const> = 14
local ETH_ALEN   <const> = 6
local MTU        <const> = 1500
local TIMEOUT_MS <const> = 500

local ifindex = linux.ifindex(IFNAME)

local function answer(...)
	local ok, err = attempt.new(socket.new, ...)
	return ok and "is taken" or "raises " .. err
end

local rx <close> = raw.new(PROTO, ifindex)
rx:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local listening <close> = socket.new(sk.af.PACKET, sk.sock.RAW, PROTO)
listening:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local swapped <close> = socket.new(sk.af.PACKET, sk.sock.RAW, PROTO_NET)
swapped:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

local tx <close> = socket.new(sk.af.PACKET, sk.sock.DGRAM, 0)
tx:send(PAYLOAD, PROTO, ifindex)

local frame = rx:receive(MTU)
local reached = listening:receive(MTU)
local missed = swapped:receive(MTU) == nil

assert(#frame >= ETH_HLEN, "short frame: " .. #frame .. " bytes")
print("socket packet: frame carries " .. string.sub(frame, ETH_HLEN + 1))
print("socket packet: destination " .. string.format(string.rep("%02x", ETH_ALEN, ":"),
	string.byte(frame, 1, ETH_ALEN)))
assert(#reached >= ETH_HLEN, "short frame on the unbound socket: " .. #reached .. " bytes")
print("socket packet: host order reaches the unbound socket")
print("socket packet: network order " .. (PROTO_NET == PROTO and "is host order" or
	missed and "misses it" or "reaches it too"))

print("socket packet: a protocol past 16 bits " .. answer(sk.af.PACKET, sk.sock.RAW, PROTO_MAX + 1))
print("socket packet: SOCK_PACKET on AF_PACKET " .. answer(sk.af.PACKET, sk.sock.PACKET, PROTO))
print("socket packet: SOCK_PACKET on AF_INET " .. answer(sk.af.INET, sk.sock.PACKET, PROTO))

