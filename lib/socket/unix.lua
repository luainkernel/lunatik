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

---
-- Binds a new UNIX domain socket to a specific path.
-- @param path (string) The UNIX domain socket path.
-- @param type (string) [optional] "STREAM" or "DGRAM".
-- @return A new UNIX domain socket object (stream by default) bound to path.
-- @raise Error if socket.new() or socket.bind() fail.
-- @see socket.new
-- @see socket.bind
function unix.bind(path, _type)
	local t = _type and string.upper(_type) or "STREAM"
	local s = socket.new(af.UNIX, sock[t], 0)
	s:bind(path)
	return s 
end

return unix

