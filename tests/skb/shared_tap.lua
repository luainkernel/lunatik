--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side sender and packet socket for the shared test (see shared.sh).

local inet   = require("socket.inet")
local raw    = require("socket.raw")
local linux  = require("linux")
local struct = require("struct")
local sk     = require("linux.socket")
local eth    = require("linux.eth").proto

local timeval = struct(sk.layout.timeval)
local unpack  = string.unpack
local format  = string.format
local insert  = table.insert

local IFNAME     <const> = "lo"
local PAYLOAD    <const> = "lunatikshared"
local MTU        <const> = 1500
local TIMEOUT_MS <const> = 500
local FRAMES     <const> = 64 -- the frames of lo read past the datagram, at most
local FLIP       <const> = 0xff -- FLIP in shared.lua
local WRITTEN_MARK <const> = 1301 -- WRITTEN_MARK in shared.lua
local SUMMED_MARK  <const> = 1302 -- SUMMED_MARK in shared.lua
local WRITTEN_PORT <const> = 5571
local SUMMED_PORT  <const> = 5572
-- offsets into a frame, from 1: past the Ethernet header, and past an IPv4 header without options
local ETHERTYPE  <const> = 13
local PROTOCOL   <const> = 24
local DPORT      <const> = 37
local CHECK      <const> = 41

local ifindex = linux.ifindex(IFNAME)
local original = PAYLOAD:byte(-1)

local function timeout(s)
	s:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
end

local function isdatagram(frame, port)
	return #frame > CHECK and unpack(">I2", frame, ETHERTYPE) == eth.IP and frame:byte(PROTOCOL) == sk.ipproto.UDP and
		unpack(">I2", frame, DPORT) == port
end

-- the frames of the datagram the packet socket holds, read once the hook has run
local function tapped(tap, port)
	local frames = {}
	for _ = 1, FRAMES do
		local frame = tap:receive(MTU, sk.msg.DONTWAIT)
		if not frame then
			break
		end
		if isdatagram(frame, port) then
			insert(frames, frame)
		end
	end
	return frames
end

local function report(cell, failure)
	print("skb shared: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

-- sends the datagram with the hook's mark and returns it as the stack delivered it and as the packet socket holds it
local function send(mark, port)
	local tap <close> = raw.new(eth.ALL, ifindex)
	local rx <close> = inet.udp()
	local tx <close> = inet.udp()
	rx:bind(inet.localhost, port)
	timeout(rx.socket)
	tx.socket:setsockopt(sk.sol.SOCKET, sk.so.NO_CHECK, 1) -- a checksum of 0, which checksum() fills
	tx.socket:setsockopt(sk.sol.SOCKET, sk.so.MARK, mark)
	tx:send(PAYLOAD, inet.localhost, port)
	return rx:receive(MTU), tapped(tap, port)
end

local function written()
	local delivered, frames = send(WRITTEN_MARK, WRITTEN_PORT)
	local failure = not delivered and "the datagram was not delivered" or
		delivered:byte(-1) ~= original ~ FLIP and "the hook's write did not reach the delivered datagram" or
		#frames == 0 and "the packet socket held no frame of it"
	for _, frame in ipairs(frames) do
		failure = failure or frame:byte(-1) ~= original and
			format("a frame the packet socket holds reads %d, not %d", frame:byte(-1), original)
	end
	report("written", failure)
end

local function summed()
	local delivered, frames = send(SUMMED_MARK, SUMMED_PORT)
	local failure = not delivered and "the datagram was not delivered" or
		#frames == 0 and "the packet socket held no frame of it"
	for _, frame in ipairs(frames) do
		local check = unpack(">I2", frame, CHECK)
		failure = failure or check ~= 0 and format("a frame the packet socket holds has checksum %04x", check)
	end
	report("summed", failure)
end

written()
summed()

