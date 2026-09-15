--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel side of the socket.unix abstract address test (see abstract.sh).
-- Binds the abstract names the shell reads back in /proc/net/unix, reports the
-- outcome of each refusal, and holds every socket for as long as the thread runs.

local unix   = require("socket.unix")
local thread = require("thread")
local linux  = require("linux")
local struct = require("struct")
local sk     = require("linux.socket")

local NONBLOCK   <const> = sk.sock.NONBLOCK
local NAME       <const> = "\0lunatikabstract"
local PREFIX     <const> = "\0lunatiklongest"
-- the longest name bind admits: UNIX_PATH_MAX less the terminator it counts
local MAXNAME    <const> = 107
local LONGEST    <const> = PREFIX .. string.rep("x", MAXNAME - #PREFIX)
local TOOLONG    <const> = LONGEST .. "x"
local BACKLOG    <const> = 1
local BUFSIZE    <const> = 64
local NAP        <const> = 10
local TIMEOUT_MS <const> = 500

local timeval = struct(sk.layout.timeval)

local server = unix.stream(NAME)
server:bind()
server:listen(BACKLOG)

local longest = unix.stream(LONGEST)
longest:bind()

local duplicate = unix.stream(NAME)
local ok, err = pcall(duplicate.bind, duplicate)
duplicate:close()
print("unix abstract: duplicate bind: " .. (ok and "bound" or err))

local toolong = unix.stream(TOOLONG)
ok, err = pcall(toolong.bind, toolong)
toolong:close()
print("unix abstract: too long bind: " .. (ok and "bound" or err))

local auto = unix.stream("")
ok, err = pcall(auto.bind, auto)
print("unix abstract: empty bind: " .. (ok and "bound" or err))

local empty = unix.stream("")
ok, err = pcall(empty.connect, empty)
empty:close()
print("unix abstract: empty connect: " .. (ok and "connected" or err))

local function serve(session)
	-- a peer may connect and send nothing, and stop() waits for this body to return
	session:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
	local received, msg = pcall(session.receive, session, BUFSIZE)
	if received and msg == "ping" then
		session:send("pong")
	end
	session:close()
end

return function()
	while not thread.shouldstop() do
		local accepted, session = pcall(server.accept, server, NONBLOCK)
		if accepted then
			serve(session)
		elseif session ~= "EAGAIN" then
			error(session)
		end
		linux.schedule(NAP)
	end
	server:close()
	longest:close()
	auto:close()
end

