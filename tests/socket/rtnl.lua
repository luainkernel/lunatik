--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket rtnl test (see rtnl.sh).

local socket   = require("socket")
local notifier = require("notifier")
local rt       = require("netlink.rt")
local net      = require("net")
local notify   = require("linux.notify")
local sk       = require("linux.socket")
local nl       = require("linux.netlink")

local PREFIX   <const> = "socket rtnl test: "
local IP_TTL   <const> = 2 -- uapi/linux/in.h
local TTL      <const> = 64
local RCVBUF   <const> = 32768
local LOOPBACK <const> = "127.0.0.1"
local DISCARD  <const> = 9

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local function request()
	local link <close> = rt.link()
	return verdict(pcall(link.list, link))
end

local function receive()
	local sock <close> = socket.new(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE)
	return verdict(pcall(sock.receive, sock, RCVBUF, sk.msg.DONTWAIT))
end

local function option(level, name, value)
	local sock <close> = socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
	return verdict(pcall(sock.setsockopt, sock, level, name, value))
end

local function send()
	local sock <close> = socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
	return verdict(pcall(sock.send, sock, PREFIX, net.aton(LOOPBACK), DISCARD))
end

local probed = false

local function cb()
	if not probed then
		probed = true
		report("request " .. request())
		report("receive " .. receive())
		report("protocol option " .. option(sk.sol.IP, IP_TTL, TTL))
		report("socket option " .. option(sk.sol.SOCKET, sk.so.RCVBUF, RCVBUF))
		report("send " .. send())
	end
	return notify.OK
end

notifier.netdevice(cb)
report("after " .. request())

