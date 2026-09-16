--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket.unix address test (see address.sh).

local unix   = require("socket.unix")
local struct = require("struct")
local sk     = require("linux.socket")

local pack = table.pack

local timeval = struct(sk.layout.timeval)

local PATH       <const> = "/tmp/lunatikaddress.sock"
local SERVER     <const> = "/tmp/lunatikaddressserver.sock"
local CLIENT     <const> = "/tmp/lunatikaddressclient.sock"
local PEER       <const> = "/tmp/lunatikaddresspeer.sock"
local CALLER     <const> = "/tmp/lunatikaddresscaller.sock"
local ABSTRACT   <const> = "\0lunatikaddress"
local PAYLOAD    <const> = "lunatikaddress"
local BACKLOG    <const> = 1
local BUFSIZE    <const> = 64
local TIMEOUT_MS <const> = 500
-- unix_autobind names a socket with a NUL and five hexadecimal digits
local AUTOBIND_LEN <const> = 6

local function say(what)
	print("unix address: " .. what)
end

-- a receive that never returns holds the runtime lock for as long as it waits
local function bounded(sock)
	sock.socket:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
	return sock
end

local unbound = unix.stream()
local empty = pack(unbound:getsockname())
assert(empty.n == 1, "getsockname answered " .. empty.n .. " values")
assert(empty[1] == "", "an unbound socket named " .. #empty[1] .. " bytes")
say("unbound getsockname is empty")
unbound:close()

local pathname = unix.stream(PATH)
pathname:bind()
local name = pack(pathname:getsockname())
assert(name.n == 1, "getsockname answered " .. name.n .. " values")
assert(name[1] == PATH, "a pathname socket named '" .. name[1] .. "'")
say("pathname getsockname ok")
pathname:close()

local abstract = unix.stream(ABSTRACT)
abstract:bind()
name = pack(abstract:getsockname())
assert(name[1] == ABSTRACT, "an abstract socket named " .. #name[1] .. " bytes")
say("abstract getsockname ok")
abstract:close()

local auto = unix.stream("")
auto:bind()
name = pack(auto:getsockname())
assert(#name[1] == AUTOBIND_LEN, "an autobound socket named " .. #name[1] .. " bytes")
assert(string.match(name[1], "^\0%x+$"), "an autobound socket named an unexpected name")
say("autobind getsockname ok")
auto:close()

local listener = unix.stream(PEER)
listener:bind()
listener:listen(BACKLOG)

local caller = unix.stream(PEER)
caller:bind(CALLER)
caller:connect()
local session = listener:accept()

local peer = pack(caller:getpeername())
assert(peer.n == 1, "getpeername answered " .. peer.n .. " values")
assert(peer[1] == PEER, "a pathname peer was named '" .. peer[1] .. "'")
say("pathname getpeername ok")

caller:send(PAYLOAD)
local streamed = pack(session:receive(BUFSIZE, sk.msg.DONTWAIT, true))
assert(streamed.n == 2, "a connected stream answered " .. streamed.n .. " values")
assert(streamed[1] == PAYLOAD and streamed[2] == CALLER,
	"a connected stream's peer was named '" .. tostring(streamed[2]) .. "'")
say("receive names a connected stream's peer")

session:close()
caller:close()

local nameless = unix.stream(PEER)
nameless:connect()
local silent = listener:accept()
name = pack(silent:getpeername())
assert(name[1] == "", "an unbound peer was named " .. #name[1] .. " bytes")
say("unbound getpeername is empty")

nameless:send(PAYLOAD)
streamed = pack(silent:receive(BUFSIZE, sk.msg.DONTWAIT, true))
assert(streamed.n == 1, "a stream from an unbound peer answered " .. streamed.n .. " values")
assert(streamed[1] == PAYLOAD, "unexpected message: " .. streamed[1])
say("receive names no unbound stream peer")

silent:close()
nameless:close()
listener:close()

local secret = unix.stream(ABSTRACT)
secret:bind()
secret:listen(BACKLOG)

local visitor = unix.stream(ABSTRACT)
visitor:connect()
local guest = secret:accept()
name = pack(visitor:getpeername())
assert(name[1] == ABSTRACT, "an abstract peer was named " .. #name[1] .. " bytes")
say("abstract getpeername ok")
guest:close()
visitor:close()
secret:close()

local server = bounded(unix.dgram(SERVER))
server:bind()

local client = unix.dgram(CLIENT)
client:bind()
client:sendto(PAYLOAD, SERVER)
local named = pack(server:receivefrom(BUFSIZE))
assert(named.n == 2, "receivefrom answered " .. named.n .. " values")
assert(named[1] == PAYLOAD and named[2] == CLIENT, "a bound peer was named '" .. tostring(named[2]) .. "'")
say("receivefrom names a pathname peer")
client:close()

local anonymous = unix.dgram()
anonymous:sendto(PAYLOAD, SERVER)
local unnamed = pack(server:receivefrom(BUFSIZE))
assert(unnamed.n == 1, "an unbound peer was named " .. unnamed.n .. " values: " .. tostring(unnamed[2]))
assert(unnamed[1] == PAYLOAD, "unexpected message: " .. unnamed[1])
say("receivefrom names no unbound peer")
anonymous:close()

local hidden = unix.dgram(ABSTRACT)
hidden:bind()
hidden:sendto(PAYLOAD, SERVER)
named = pack(server:receivefrom(BUFSIZE))
assert(named.n == 2, "receivefrom answered " .. named.n .. " values")
assert(named[2] == ABSTRACT, "an abstract peer was named " .. #tostring(named[2]) .. " bytes")
say("receivefrom names an abstract peer")
hidden:close()
server:close()

