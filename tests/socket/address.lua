--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket address test (see address.sh).

local socket = require("socket")
local raw    = require("socket.raw")
local linux  = require("linux")
local struct = require("struct")
local net    = require("net")
local sk     = require("linux.socket")
local nl     = require("linux.netlink")
local eth    = require("linux.eth")

local pack = table.pack

local timeval = struct(sk.layout.timeval)

local LOOPBACK   <const> = net.aton("127.0.0.1")
local IFNAME     <const> = "lo"
local PROTO      <const> = eth["802_EX1"]
local PAYLOAD    <const> = "lunatikaddress"
local BUFSIZE    <const> = 64
local MTU        <const> = 1500
local BACKLOG    <const> = 1
local TIMEOUT_MS <const> = 500
-- ARPHRD_LOOPBACK, which no autogen table carries (<uapi/linux/if_arp.h>)
local HATYPE     <const> = 772
-- struct sockaddr_ll past the family, unbound and bound to a loopback interface
local PACKET_UNBOUND  <const> = 10
local PACKET_BOUND    <const> = 16
-- packet_recvmsg widens a sockaddr_ll short of the whole struct
local PACKET_RECEIVED <const> = 18
-- struct sockaddr_in6 past the family: port, flow info, address, scope id
local INET6_LEN    <const> = 26
local IN6_LOOPBACK <const> = string.rep("\0", 15) .. "\1"
local IN6_ANYPORT  <const> = string.pack(">I2", 0) .. string.pack("=I4", 0) .. IN6_LOOPBACK .. string.pack("=I4", 0)

local function say(what)
	print("socket address: " .. what)
end

local function supported(family, type, proto)
	local ok, sock = pcall(socket.new, family, type, proto)
	if ok then
		sock:close()
	end
	return ok
end

-- a receive that never returns holds the runtime lock for as long as it waits
local function bounded(sock)
	sock:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
	return sock
end

local ifindex = linux.ifindex(IFNAME)

local udp = bounded(socket.new(sk.af.INET, sk.sock.DGRAM, 0))
udp:bind(LOOPBACK, 0)
local bound = pack(udp:getsockname())
assert(bound.n == 2, "getsockname answered " .. bound.n .. " values")
assert(bound[1] == LOOPBACK and bound[2] ~= 0, "unexpected local address: " .. bound[1] .. ":" .. bound[2])
say("inet getsockname ok")

local server = socket.new(sk.af.INET, sk.sock.STREAM, 0)
server:bind(LOOPBACK, 0)
server:listen(BACKLOG)
local _, listening = server:getsockname()

local client = socket.new(sk.af.INET, sk.sock.STREAM, 0)
local ok, err = pcall(client.getpeername, client)
assert(not ok and err == "ENOTCONN", "an unconnected getpeername answered: " .. tostring(err))
say("inet getpeername unconnected refused")

-- without an explicit flags argument connect takes the port for the flags
client:connect(LOOPBACK, listening, 0)
local session = bounded(server:accept())
local peer = pack(client:getpeername())
assert(peer.n == 2, "getpeername answered " .. peer.n .. " values")
assert(peer[1] == LOOPBACK and peer[2] == listening, "unexpected peer: " .. peer[1] .. ":" .. peer[2])
say("inet getpeername ok")

local sender = socket.new(sk.af.INET, sk.sock.DGRAM, 0)
sender:send(PAYLOAD, LOOPBACK, bound[2])
local datagram = pack(udp:receive(BUFSIZE, 0, true))
assert(datagram.n == 3, "receivefrom answered " .. datagram.n .. " values")
assert(datagram[1] == PAYLOAD and datagram[2] == LOOPBACK and datagram[3] ~= 0,
	"unexpected sender: " .. datagram[2] .. ":" .. datagram[3])
say("inet receivefrom ok")
sender:close()
udp:close()

client:send(PAYLOAD)
local stream = pack(session:receive(BUFSIZE, 0, true))
assert(stream.n == 1, "a connected TCP socket answered " .. stream.n .. " values")
assert(stream[1] == PAYLOAD, "unexpected message: " .. stream[1])
say("inet receive names no sender")
session:close()
client:close()
server:close()

local nlsock = bounded(socket.new(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE))
nlsock:bind(0, 0)
local netlink = pack(nlsock:getsockname())
assert(netlink.n == 2, "getsockname answered " .. netlink.n .. " values")
assert(netlink[1] ~= 0 and netlink[2] == 0, "unexpected netlink address: " .. netlink[1] .. "/" .. netlink[2])
say("netlink getsockname ok")

nlsock:send(PAYLOAD, netlink[1], 0)
local unicast = pack(nlsock:receive(BUFSIZE, 0, true))
assert(unicast.n == 3, "receivefrom answered " .. unicast.n .. " values")
assert(unicast[2] == netlink[1] and unicast[3] == 0, "unexpected netlink sender: " .. unicast[2] .. "/" .. unicast[3])
say("netlink receivefrom ok")
nlsock:close()

if supported(sk.af.INET6, sk.sock.DGRAM, 0) then
	local udp6 = socket.new(sk.af.INET6, sk.sock.DGRAM, 0)
	udp6:bind(IN6_ANYPORT)
	local address = pack(udp6:getsockname())
	assert(address.n == 1, "getsockname answered " .. address.n .. " values")
	assert(#address[1] == INET6_LEN, "inet6 getsockname answered " .. #address[1] .. " bytes")
	local port, _, host = string.unpack(">I2=I4c16", address[1])
	assert(port ~= 0 and host == IN6_LOOPBACK, "unexpected inet6 address on port " .. port)
	say("inet6 getsockname ok")
	udp6:close()
else
	say("inet6 unsupported")
end

if supported(sk.af.PACKET, sk.sock.RAW, eth.ALL) then
	local packet = socket.new(sk.af.PACKET, sk.sock.RAW, eth.ALL)
	local unbound = packet:getsockname()
	assert(#unbound == PACKET_UNBOUND, "an unbound packet getsockname answered " .. #unbound .. " bytes")
	local _, index, hatype, pkttype, halen = string.unpack(">I2=i4I2BB", unbound)
	assert(index == 0 and hatype == 0 and pkttype == 0 and halen == 0,
		"unexpected unbound packet address on interface " .. index)
	say("packet getsockname unbound ok")

	packet:bind(PROTO, ifindex)
	local address = packet:getsockname()
	assert(#address == PACKET_BOUND, "a bound packet getsockname answered " .. #address .. " bytes")
	local proto, index, hatype, pkttype, halen, hwaddr = string.unpack(">I2=i4I2BBc6", address)
	assert(proto == PROTO and index == ifindex and hatype == HATYPE and pkttype == 0,
		"unexpected bound packet address on interface " .. index)
	assert(halen == #hwaddr and hwaddr == string.rep("\0", #hwaddr), "unexpected hardware address")
	say("packet getsockname bound ok")
	packet:close()

	local receiver = bounded(raw.bind(PROTO, ifindex))
	local transmitter = socket.new(sk.af.PACKET, sk.sock.DGRAM, 0)
	transmitter:send(PAYLOAD, PROTO, ifindex)
	transmitter:close()
	local frame = pack(receiver:receive(MTU, 0, true))
	assert(frame.n == 2, "receivefrom answered " .. frame.n .. " values")
	assert(#frame[2] == PACKET_RECEIVED, "a packet receivefrom answered " .. #frame[2] .. " bytes")
	local source, index = string.unpack(">I2=i4", frame[2])
	assert(source == PROTO and index == ifindex, "unexpected frame source on interface " .. index)
	say("packet receivefrom ok")
	receiver:close()
else
	say("packet unsupported")
end

