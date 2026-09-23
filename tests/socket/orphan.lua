--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket orphan test (see orphan.sh).

local socket = require("socket")
local signal = require("signal")
local linux  = require("linux")
local net    = require("net")
local sk     = require("linux.socket")
local pids   = require("tests.netns_pid")

local LOOPBACK <const> = net.aton("127.0.0.1")
local PORT     <const> = 6923
local BACKLOG  <const> = 1
local TRIES    <const> = 50
local WAIT     <const> = 100 -- ms between tries

local function say(what)
	print("socket orphan: " .. what)
end

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, 0, pids.holder)
end

local function reachable()
	local ok, probe = pcall(tcpsocket)
	if ok then
		probe:close()
	end
	return ok
end

local ok, listener = pcall(tcpsocket)
if not ok and listener == "EOPNOTSUPP" then
	say("a task's namespace is refused: EOPNOTSUPP")
	return
end
assert(ok, "a socket in the holder's namespace was refused: " .. tostring(listener))
listener:bind(LOOPBACK, PORT)
listener:listen(BACKLOG)

local client <close> = tcpsocket()
client:connect(LOOPBACK, PORT)
local accepted <close> = listener:accept()
say("connected and accepted in the namespace")
listener:close()

signal.kill(pids.holder)
local tries = 0
while reachable() do
	tries = tries + 1
	assert(tries < TRIES, "the holder did not exit")
	linux.schedule(WAIT)
end

