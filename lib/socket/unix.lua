--
-- SPDX-FileCopyrightText: (c) 2025-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- UNIX domain socket (AF_UNIX) operations.
-- This module provides an OOP-style abstraction over the `socket` module for
-- AF_UNIX sockets, modeled after `socket.inet`.
--
-- A socket instance can be created with an optional path stored as default
-- address, which is then reused automatically in `bind`, `connect`, and
-- `dgram:sendto` without an explicit per-call address.
--
-- @module socket.unix
-- @see socket
-- @see socket.inet
--
local socket = require("socket")

local af   = require("linux.socket").af
local sock = require("linux.socket").sock

---
-- Base class for UNIX domain socket objects.
-- @type unix
local unix = {}

---
-- Constructor for unix socket objects.
-- Initializes a new socket object and sets up its metatable.
-- @param o (table) [optional] An initial table to use as the object.
-- @return (table) The new unix socket object.
function unix:new(o)
	local o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

---
-- Creates a new UNIX domain socket instance.
-- This is the primary way to create instances (e.g. `local s = unix.stream(path)`).
-- @param path (string) [optional] Default UNIX socket path stored in the object.
--   Reused automatically by `bind`, `connect`, `send`, `sendto`, and `receivefrom`
--   when no explicit path is given.
-- @return (table) A new unix socket object.
-- @see socket.new
function unix:__call(path)
	local o = self:new{path = path}
	o.socket = socket.new(af.UNIX, self.type, 0)
	return o
end

---
-- Closes the underlying socket.
-- @see socket.close
function unix:close()
	self.socket:close()
end

---
-- Binds the socket to a UNIX domain path.
-- @param path (string) [optional] Path to bind to.
--   Defaults to the path provided at construction time.
-- @see socket.bind
function unix:bind(path)
	self.socket:bind(path or self.path)
end

---
-- Connects the socket to a UNIX domain path.
-- @param path (string) [optional] Path to connect to.
--   Defaults to the path provided at construction time.
-- @see socket.connect
function unix:connect(path)
	self.socket:connect(path or self.path)
end

---
-- Sends data through the socket.
-- For connected STREAM sockets, `path` is omitted. For DGRAM sockets,
-- use `sendto()` to send to the stored path or an explicit destination.
-- @param msg (string) The message to send.
-- @param path (string) [optional] Explicit destination socket path.
-- @return (number) Number of bytes sent on success.
-- @raise error on failure.
-- @see socket.send
function unix:send(msg, path)
	return path and self.socket:send(msg, path) or self.socket:send(msg)
end

---
-- Receives data from the socket.
-- @param ... Varargs passed directly to `socket:receive()`.
-- @return Varargs returned by `socket:receive()`.
-- @see socket.receive
function unix:receive(...)
	return self.socket:receive(...)
end

---
-- Gets the local address (path) of the socket.
-- @return (string) The local socket path.
-- @see socket.getsockname
function unix:getsockname()
	return self.socket:getsockname()
end

---
-- Gets the remote address (path) the socket is connected to.
-- @return (string) The remote socket path.
-- @see socket.getpeername
function unix:getpeername()
	return self.socket:getpeername()
end

---
-- STREAM socket specialization (connection-oriented).
-- Create instances with `unix.stream([path])`.
-- @table unix.stream
-- @field type The socket type (`linux.socket.sock.STREAM`).
unix.stream = unix:new{type = sock.STREAM}

---
-- Listens for incoming connections on a STREAM socket.
-- @param backlog (number) Maximum length of the queue of pending connections.
-- @see socket.listen
function unix.stream:listen(backlog)
	self.socket:listen(backlog)
end

---
-- Accepts an incoming connection on a listening STREAM socket.
-- @param flags (number) [optional] Flags for the accept operation.
-- @return A new socket object for the accepted connection.
-- @see socket.accept
function unix.stream:accept(flags)
	return self.socket:accept(flags)
end

---
-- DGRAM socket specialization (connectionless).
-- Create instances with `unix.dgram([path])`.
-- The optional path is stored as the default destination for `sendto`.
-- @table unix.dgram
-- @field type The socket type (`linux.socket.sock.DGRAM`).
unix.dgram = unix:new{type = sock.DGRAM}

---
-- Receives data from a DGRAM socket along with the sender's path.
-- @param len (number) [optional] Maximum number of bytes to receive.
-- @param flags (number) [optional] Receive flags.
-- @return (string or nil) The received data.
-- @return (string or nil) The sender's socket path.
-- @see socket.receive
function unix.dgram:receivefrom(len, flags)
	return self:receive(len, flags, true)
end

---
-- Sends data to a UNIX domain socket path.
-- If `path` is omitted, uses the path provided at construction time.
-- @param msg (string) The message to send.
-- @param path (string) [optional] Destination socket path.
-- @return (number) Number of bytes sent on success.
-- @raise error on failure.
-- @see unix.send
function unix.dgram:sendto(msg, path)
	local dest = path or self.path
	return dest and self.socket:send(msg, dest) or self.socket:send(msg)
end

return unix

