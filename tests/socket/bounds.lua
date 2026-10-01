--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket bounds test (see bounds.sh).

local socket = require("socket")
local net    = require("net")
local test   = require("tests.lib").test
local sk     = require("linux.socket")
local nl     = require("linux.netlink")

local LOOPBACK    <const> = net.aton("127.0.0.1")
local PORT        <const> = 9 -- discard: nothing needs to listen for a UDP send or connect
local PAYLOAD     <const> = "lunatikbounds"
local BUFSIZE     <const> = 64
local RCVBUF      <const> = 32768
local U32         <const> = 1 << 32 -- past an int, a u32 and an unsigned int alike
local INT_MAX     <const> = (1 << 31) - 1
local INT_MIN     <const> = -(1 << 31)
local OUTOFBOUNDS <const> = "out of bounds"
local INVALID     <const> = "invalid IPv4 address"

local addresses = {
	["0.0.0.0"]         = 0,
	["127.0.0.1"]       = 0x7f000001,
	["10.20.30.40"]     = 0x0a141e28,
	["255.255.255.255"] = 0xffffffff,
}

local notaddresses = {"300.1.1.1", "256.0.0.0", "1.2.3", "1.2.3.4.5", "1.2.3.04", "-1.2.3.4", " 1.2.3.4",
	"1.2.3.4 ", "1..2.3", "0x7f.0.0.1", "localhost", ""}

local function refuses(what, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " was accepted")
	assert(tostring(err):match(OUTOFBOUNDS), what .. " raised something else: " .. tostring(err))
end

local function invalid(addr)
	local ok, err = pcall(net.aton, addr)
	assert(not ok, ("net.aton accepted %q"):format(addr))
	assert(tostring(err):find(INVALID, 1, true), ("net.aton raised something else for %q: %s"):format(addr, err))
end

local function udp()
	return socket.new(sk.af.INET, sk.sock.DGRAM, 0)
end

test("socket.new refuses a family, a type or a protocol past an int", function()
	refuses("a family past 32 bits", socket.new, sk.af.INET | U32, sk.sock.DGRAM, 0)
	refuses("a family below INT_MIN", socket.new, INT_MIN - 1, sk.sock.DGRAM, 0)
	refuses("a type past 32 bits", socket.new, sk.af.INET, sk.sock.DGRAM | U32, 0)
	refuses("a type below INT_MIN", socket.new, sk.af.INET, INT_MIN - 1, 0)
	refuses("a protocol past 32 bits", socket.new, sk.af.INET, sk.sock.DGRAM, U32)
	refuses("a protocol below INT_MIN", socket.new, sk.af.INET, sk.sock.DGRAM, INT_MIN - 1)
end)

test("an AF_INET address past 32 bits is refused by bind, connect and send", function()
	local sock <close> = udp()
	refuses("a bind to an address past 32 bits", sock.bind, sock, LOOPBACK | U32, 0)
	refuses("a bind to a negative address", sock.bind, sock, -1, 0)
	refuses("a connect to an address past 32 bits", sock.connect, sock, LOOPBACK | U32, PORT)
	refuses("a send to an address past 32 bits", sock.send, sock, PAYLOAD, LOOPBACK | U32, PORT)
end)

test("an AF_NETLINK port id or group mask past 32 bits is refused", function()
	local pid <close> = socket.new(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE)
	refuses("a port id past 32 bits", pid.bind, pid, U32, 0)
	refuses("a negative port id", pid.bind, pid, -1, 0)
	refuses("a connect to a port id past 32 bits", pid.connect, pid, U32, 0)
	local groups <close> = socket.new(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE)
	refuses("a group mask past 32 bits", groups.bind, groups, 0, U32)
end)

-- DONTWAIT, so a receive the bound misses returns; -1 first, which a build without it fails before allocating
test("receive refuses a length below 0 or past INT_MAX", function()
	local sock <close> = udp()
	refuses("a negative length", sock.receive, sock, -1, sk.msg.DONTWAIT)
	refuses("a length past INT_MAX", sock.receive, sock, INT_MAX + 1, sk.msg.DONTWAIT)
end)

test("receive, connect, accept and listen refuse flags or a backlog past an int", function()
	local sock <close> = udp()
	refuses("receive flags past 32 bits", sock.receive, sock, BUFSIZE, sk.msg.DONTWAIT | U32)
	refuses("connect flags past 32 bits", sock.connect, sock, LOOPBACK, PORT, U32)

	local server <close> = socket.new(sk.af.INET, sk.sock.STREAM, 0)
	server:bind(LOOPBACK, 0)
	refuses("a backlog past 32 bits", server.listen, server, U32)
	server:listen()
	refuses("accept flags past 32 bits", server.accept, server, sk.sock.NONBLOCK | U32)
end)

test("setsockopt refuses a level, a name or an integer value past 32 bits", function()
	local sock <close> = udp()
	refuses("a level past 32 bits", sock.setsockopt, sock, sk.sol.SOCKET | U32, sk.so.RCVBUF, RCVBUF)
	refuses("a name past 32 bits", sock.setsockopt, sock, sk.sol.SOCKET, sk.so.RCVBUF | U32, RCVBUF)
	refuses("a value past 32 bits", sock.setsockopt, sock, sk.sol.SOCKET, sk.so.RCVBUF, RCVBUF | U32)
	refuses("a value below INT_MIN", sock.setsockopt, sock, sk.sol.SOCKET, sk.so.RCVBUF, INT_MIN - 1)
end)

test("setsockopt takes an unsigned option's 32 bits, past INT_MAX", function()
	local sock <close> = udp()
	sock:setsockopt(sk.sol.SOCKET, sk.so.MARK, U32 - 1)
	sock:setsockopt(sk.sol.SOCKET, sk.so.MARK, INT_MIN)
end)

test("net.aton reads four decimal octets from 0 to 255", function()
	for addr, ip in pairs(addresses) do
		local got = net.aton(addr)
		assert(got == ip, ("net.aton read %q as %d"):format(addr, got))
	end
end)

test("net.aton refuses anything but four decimal octets from 0 to 255", function()
	for _, addr in ipairs(notaddresses) do
		invalid(addr)
	end
end)

