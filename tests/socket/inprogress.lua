--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket inprogress test (see inprogress.sh).

local socket = require("socket")
local struct = require("struct")
local net    = require("net")
local sk     = require("linux.socket")
local pids   = require("tests.netns_pid")

local format = string.format

local LOOPBACK   <const> = net.aton("127.0.0.1")
-- the port the test's nft rule drops every segment to
local PORT       <const> = 6924
local MESSAGE    <const> = "inprogress"
local TIMEOUT_MS <const> = 100
local NONBLOCK   <const> = sk.sock.NONBLOCK

local timeval = struct(sk.layout.timeval)

local function say(what)
	print("socket inprogress: " .. what)
end

local function pending(what, expected, connected, err)
	assert(connected == nil and err == expected, format("%s answered %s, %s", what, connected, err))
	say(what .. " answers nil and " .. expected)
end

local ok, client = pcall(socket.new, sk.af.INET, sk.sock.STREAM, 0, pids.holder)
if not ok and client == "EOPNOTSUPP" then
	say("a task's namespace is refused: EOPNOTSUPP")
	return
end
assert(ok, "a socket in the holder's namespace was refused: " .. tostring(client))
client:setsockopt(sk.sol.SOCKET, sk.so.SNDTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))

pending("a timed connect", "EINPROGRESS", client:connect(LOOPBACK, PORT))
pending("a timed connect called again", "EALREADY", client:connect(LOOPBACK, PORT))
pending("a nonblocking connect called again", "EALREADY", client:connect(LOOPBACK, PORT, NONBLOCK))

local sent, extra = client:send(MESSAGE)
assert(sent == false and extra == nil, format("a timed send while connecting answered %s, %s", sent, extra))
say("a timed send while connecting answers false")
client:close()

