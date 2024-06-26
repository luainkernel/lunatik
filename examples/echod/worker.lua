--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local thread = require("thread")
local socket = require("socket")
local data   = require("data")

local shouldstop = thread.shouldstop

local function info(id, message)
	local prefix = "echod [worker #" .. id .. "]"
	print(string.format("%s: %s", prefix, message))
end

local function alive(control)
	return control:getbyte(1) ~= 0
end

local function echo(session)
	local message = session:receive(1024)
	session:send(message)
	return message == ""
end

local function worker(control, session)
	local id = control:getbyte(0)

	info(id, "started")
	repeat
		local ok, err = pcall(echo, session)
		if not ok then
			return info(id, "aborted")
		end
	until (not alive(control) or err or shouldstop())
	info(id, "stopped")
end

return worker

