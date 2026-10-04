--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the checksum test (see checksum.sh).

local netfilter = require("netfilter")
local byteorder = require("byteorder")
local nf        = require("linux.nf")

local PRIORITY <const> = 0x12370000
local PAYLOAD  <const> = 256
local DELTA    <const> = 16
local SHORT    <const> = 26
local IHL4     <const> = 4
local ONES     <const> = 0xffff

local IP_TOTLEN   <const> = 2
local IP_CHECK    <const> = 10
local IP_ADDRS    <const> = 12
local IP_ADDRSLEN <const> = 8
local IP6_ADDRS    <const> = 8
local IP6_ADDRSLEN <const> = 32
local IP6_HDRLEN   <const> = 40
local TCP_CHECK <const> = 16
local UDP_CHECK <const> = 6
local UDP_HDRLEN <const> = 8
local TCP <const> = 6
local UDP <const> = 17

local pending = {
	[PRIORITY + 1] = "fits4",
	[PRIORITY + 2] = "fits6",
	[PRIORITY + 3] = "below4",
	[PRIORITY + 4] = "past4",
	[PRIORITY + 5] = "past6",
	[PRIORITY + 6] = "ext6",
	[PRIORITY + 7] = "short4",
	[PRIORITY + 8] = "ihl4",
	[PRIORITY + 9] = "zero6",
}

local function iphlen(data)
	return (data:getuint8(0) & 0x0f) * 4
end

local function fold(sum)
	while sum > ONES do
		sum = (sum & ONES) + (sum >> 16)
	end
	return sum
end

-- data:checksum complements the folded sum; a segment and its pseudo-header that verify fold to ONES
local function summed(data, addrs, addrslen, offset, proto)
	local len = #data - offset
	local sum = (ONES - data:checksum(addrs, addrslen)) + (ONES - data:checksum(offset, len)) +
		byteorder.hton16(proto) + byteorder.hton16(len)
	return fold(sum) == ONES
end

local function unchanged(data, before)
	return data:getstring(0, #data) == before
end

local function shrink(skb)
	skb:resize(#skb - DELTA)
	return skb:data()
end

local prepare = {}

function prepare.fits4(skb)
	local data = skb:data()
	data:setuint16(IP_CHECK, 0)
	data:setuint16(iphlen(data) + TCP_CHECK, 0)
	return data
end

function prepare.fits6(skb)
	local data = skb:data()
	data:setuint16(IP6_HDRLEN + UDP_CHECK, 0)
	return data
end

-- the first payload word takes the value that makes the datagram's sum fold to 0
function prepare.zero6(skb)
	local data = prepare.fits6(skb)
	local word = IP6_HDRLEN + UDP_HDRLEN
	local len = #data - IP6_HDRLEN
	data:setuint16(word, 0)
	local sum = (ONES - data:checksum(IP6_ADDRS, IP6_ADDRSLEN)) + (ONES - data:checksum(IP6_HDRLEN, len)) +
		byteorder.hton16(UDP) + byteorder.hton16(len)
	data:setuint16(word, ONES - fold(sum))
	return data
end

function prepare.below4(skb)
	local data = skb:data()
	data:setuint16(IP_TOTLEN, byteorder.hton16(iphlen(data) - 1))
	return data
end

function prepare.ext6(skb)
	return skb:data()
end

function prepare.short4(skb)
	skb:resize(SHORT)
	local data = skb:data()
	data:setuint16(IP_TOTLEN, byteorder.hton16(SHORT))
	return data
end

function prepare.ihl4(skb)
	local data = skb:data()
	data:setuint8(0, (data:getuint8(0) & 0xf0) | IHL4)
	return data
end

prepare.past4 = shrink
prepare.past6 = shrink

local verify = {
	below4 = unchanged,
	past4  = unchanged,
	past6  = unchanged,
	ext6   = unchanged,
	short4 = unchanged,
	ihl4   = unchanged,
}

function verify.fits4(data)
	local hlen = iphlen(data)
	return data:checksum(0, hlen) == 0 and summed(data, IP_ADDRS, IP_ADDRSLEN, hlen, TCP)
end

function verify.fits6(data)
	return summed(data, IP6_ADDRS, IP6_ADDRSLEN, IP6_HDRLEN, UDP)
end

function verify.zero6(data)
	return data:getuint16(IP6_HDRLEN + UDP_CHECK) == ONES and verify.fits6(data)
end

local function checksum_hook(skb)
	local priority = skb:priority()
	local name = pending[priority]
	if name == nil or #skb < PAYLOAD then
		return nf.action.ACCEPT
	end
	pending[priority] = nil
	local data = prepare[name](skb)
	local before = data:getstring(0, #data)
	skb:checksum()
	print("skb checksum: " .. name .. (verify[name](data, before) and " ok" or " FAIL"))
	return nf.action.DROP
end

netfilter.register{
	hook     = checksum_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

