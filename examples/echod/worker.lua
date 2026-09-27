--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local thread = require("thread")
local struct = require("struct")
local sk     = require("linux.socket")

local shouldstop = thread.shouldstop
local timeval = struct(sk.layout.timeval)

local SIZE       <const> = 1024
local TIMEOUT_MS <const> = 100 -- nothing stops a worker: an idle client holds a receive this long at most

local function info(id, message)
	local prefix = "echod [worker #" .. id .. "]"
	print(string.format("%s: %s", prefix, message))
end

local function alive(control)
	return control:getbyte(1) ~= 0
end

local function echo(session)
	local ok, message = pcall(session.receive, session, SIZE)
	if not ok then
		if message ~= "EAGAIN" then
			error(message, 0)
		end
		return false
	end
	session:send(message)
	return message == ""
end

local function worker(control, session)
	local id = control:getbyte(0)

	info(id, "started")
	session:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
	repeat
		local ok, err = pcall(echo, session)
		if not ok then
			return info(id, "aborted")
		end
	until (not alive(control) or err or shouldstop())
	info(id, "stopped")
end

return worker

