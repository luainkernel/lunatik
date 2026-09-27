--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local thread = require("thread")
local linux  = require("linux")

local shouldstop = thread.shouldstop
local DONTWAIT = require("linux.socket").msg.DONTWAIT

local function info(id, message)
	local prefix = "echod [worker #" .. id .. "]"
	print(string.format("%s: %s", prefix, message))
end

local function alive(control)
	return control:getbyte(1) ~= 0
end

local function echo(session)
	local message = session:receive(1024, DONTWAIT)
	session:send(message)
	return message == ""
end

local function worker(control, session)
	local id = control:getbyte(0)
	local done

	info(id, "started")
	repeat
		local ok, eof = pcall(echo, session)
		if ok then
			done = eof
		elseif eof == "EAGAIN" then
			linux.schedule(100)
		else
			return info(id, "aborted")
		end
	until (done or not alive(control) or shouldstop())
	info(id, "stopped")
end

return worker

