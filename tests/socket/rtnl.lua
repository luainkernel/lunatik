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

local insert = table.insert

local PREFIX   <const> = "socket rtnl test: "
local REFUSAL  <const> = "not allowed under RTNL"
local IP_TTL   <const> = 2 -- uapi/linux/in.h
local IP_ADD_MEMBERSHIP <const> = 35 -- uapi/linux/in.h
local MCAST    <const> = 0xE00000FB -- 224.0.0.251
local MREQ     <const> = string.pack(">I4I4=i4", MCAST, 0, 0) -- an ip_mreqn with no address and no interface
local GROUP    <const> = 1
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

-- closed once the registration returned: a collector may run in a later callback, as socket.new says
local unclosed = {}

local function close(family, type, protocol)
	local sock = socket.new(family, type, protocol)
	local ok, err = pcall(sock.close, sock)
	if not ok then
		insert(unclosed, sock)
	end
	return verdict(ok, err)
end

local function scope()
	local sock <close> = socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
end

local function twice()
	local sock <close> = socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
	sock:close()
end

local function bind(protocol)
	local sock = socket.new(sk.af.NETLINK, sk.sock.RAW, protocol)
	insert(unclosed, sock)
	return verdict(pcall(sock.bind, sock, 0, GROUP))
end

-- a group the script could not join leaves no membership to refuse
local function membership(sock, joined)
	return joined and verdict(pcall(sock.close, sock)) or "unavailable"
end

-- the memberships are joined off RTNL, before the registration: the option is refused under it
local member = socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
local joined = pcall(member.setsockopt, member, sk.sol.IP, IP_ADD_MEMBERSHIP, MREQ)
-- an IPv6 socket joins an IPv4 group through SOL_IP too, and its release ends in inet_release
local created6, member6 = pcall(socket.new, sk.af.INET6, sk.sock.DGRAM, sk.ipproto.UDP)
local joined6 = created6 and pcall(member6.setsockopt, member6, sk.sol.IP, IP_ADD_MEMBERSHIP, MREQ)

local probed = false

local function cb()
	if not probed then
		probed = true
		local received = receive()
		report("receive " .. received)
		if received == REFUSAL then -- a request the loaded luasocket does not refuse wedges the host
			report("request " .. request())
		end
		report("protocol option " .. option(sk.sol.IP, IP_TTL, TTL))
		report("socket option " .. option(sk.sol.SOCKET, sk.so.RCVBUF, RCVBUF))
		report("send " .. send())
		report("close " .. close(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP))
		report("scoped close " .. verdict(pcall(scope)))
		report("closed twice " .. verdict(pcall(twice)))
		report("route bind " .. bind(nl.proto.ROUTE))
		local packet = close(sk.af.PACKET, sk.sock.RAW, 0)
		report("packet close " .. packet)
		-- a close the loaded luasocket does not refuse waits on a lock, or wedges the host
		if packet == REFUSAL then
			report("genl close " .. close(sk.af.NETLINK, sk.sock.RAW, nl.proto.GENERIC))
			report("genl bind " .. bind(nl.proto.GENERIC))
			report("membership close " .. membership(member, joined))
			report("inet6 membership close " .. membership(member6, joined6))
		end
	end
	return notify.OK
end

notifier.netdevice(cb)
report("after " .. request())
report("after close " .. verdict(pcall(member.close, member)))
if joined6 then
	report("after inet6 close " .. verdict(pcall(member6.close, member6)))
end
for _, sock in ipairs(unclosed) do
	sock:close()
end

