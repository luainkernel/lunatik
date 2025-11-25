--
-- SPDX-FileCopyrightText: (c) 2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- UNIX domain socket (AF_UNIX) operations.
-- This module provides a higher-level abstraction over the `socket` module.
--
-- @module socket.unix
-- @see socket
--
local socket = require("socket")

local af   = socket.af
local sock = socket.sock

local unix = {}

local function new(method)
	unix[method] = function (path, type)
		local type = type and string.upper(type) or "STREAM"
		local sock = socket.new(af.UNIX, sock[type], 0)
		sock[method](sock, path)
		return sock
	end
end

---
-- Creates and binds a new UNIX domain socket to a specific path.
-- @param path (string) The UNIX domain socket path.
-- @param type (string) [optional] "STREAM" or "DGRAM".
-- @return A new UNIX domain socket object (stream by default) bound to path.
-- @raise Error if socket.new() or socket.bind() fail.
-- @see socket.new
-- @see socket.bind
new("bind")

---
-- Creates and connects a new UNIX domain socket to a specific path.
-- @param path (string) The UNIX domain socket path.
-- @param type (string) [optional] "STREAM" or "DGRAM".
-- @return A new UNIX domain socket object (stream by default) connected to path.
-- @raise Error if socket.new() or socket.connect() fail.
-- @see socket.new
-- @see socket.connect
new("connect")

return unix

