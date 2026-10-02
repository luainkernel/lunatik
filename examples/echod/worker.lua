--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local thread = require("thread")

local shouldstop = thread.shouldstop

local SIZE <const> = 1024

local function info(id, message)
	local prefix = "echod [worker #" .. id .. "]"
	print(string.format("%s: %s", prefix, message))
end

local function echo(session)
	local message = session:receive(SIZE)
	session:send(message)
	return message == ""
end

local function serve(session)
	repeat
		local ok, err = pcall(echo, session)
		if not ok then
			return shouldstop()
		end
	until (err or shouldstop())
	return true
end

local function worker(number, connection, done)
	local id = number:getint64(0)
	local session <close> = connection -- the daemon's own handle holds the socket until it collects it

	info(id, "started")
	info(id, serve(session) and "stopped" or "aborted")
	done:setbyte(0, 1)
end

return worker

