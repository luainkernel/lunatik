--
-- SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only 
--

---
-- Internet (AF_INET) socket operations.
-- This module provides a higher-level abstraction over the raw `socket` and `net`
-- modules for creating and managing INET (IPv4) sockets, including TCP and UDP.
--
-- It simplifies common socket operations like binding, connecting, sending,
-- and receiving data.
--
-- @module socket.inet
-- @see socket
--

local socket = require("socket")
local net = require("net")

---
-- Base class for socket types.
-- @type inet
-- @field localhost (string) The loopback address '127.0.0.1'.
local inet = {localhost = '127.0.0.1'}

---
-- Constructor for inet socket objects.
-- Initializes a new socket object, setting up its metatable for OOP-like behavior.
-- @param o (table) [optional] An initial table to be used as the object.
-- @return (table) The new inet socket object.
function inet:new(o)
	local o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

local af = socket.af
---
-- Metamethod to create a new socket instance when `inet()` or `inet.tcp()` or `inet.udp()` is called.
-- This is the primary way to create new socket instances (e.g., `local sock = inet.tcp()`).
-- @return (table) A new socket object (e.g., a TCP or UDP socket object).
-- @see socket.new
-- @usage
-- local tcp_socket = inet.tcp()
-- local udp_socket = inet.udp()
function inet:__call()
	local o = self:new()
	o.socket = socket.new(af.INET, self.type, self.proto)
	return o
end

---
-- Closes the underlying socket.
-- @see socket.close
function inet:close()
	self.socket:close()
end

---
-- Receives data from the socket.
-- For UDP, if the `raw` parameter (third boolean) is true, it returns the raw IP address.
-- @param ... Varargs passed directly to the underlying `socket:receive()`.
-- Typically `(len, flags, raw_ip_for_udp)`.
-- @return Varargs returned by the underlying `socket:receive()`.
-- Typically `(data, ip_address, port)` or `(data, error_message)`.
-- @see socket.receive
function inet:receive(...)
	return self.socket:receive(...)
end

---
-- Sends data through the socket.
-- If `addr` and `port` are provided (typical for UDP), the address is converted
-- using `net.aton` before sending.
-- @param msg (string) The message to send.
-- @param addr (string) [optional] The destination IP address (e.g., for UDP).
-- @param port (number) [optional] The destination port (e.g., for UDP).
-- @return (number) Number of bytes sent on success
-- @raise error on failure
-- @see socket.send
function inet:send(msg, addr, port)
	local sock = self.socket
	return not addr and sock:send(msg) or sock:send(msg, net.aton(addr), port)
end

---
-- Binds the socket to a specific address and port.
-- The address '*' is treated as `INADDR_ANY` (0.0.0.0).
-- @param addr (string) The IP address to bind to. Use '*' for any address.
-- @param port (number) The port number to bind to.
-- @return (boolean or nil) True on success, or nil and an error message on failure.
-- @see socket.bind
function inet:bind(addr, port)
	local ip = addr ~= '*' and net.aton(addr) or 0
	return self.socket:bind(ip, port)
end

---
-- Connects the socket to a remote address and port.
-- @param addr (string) The remote IP address.
-- @param port (number) The remote port.
-- @param flags (number) [optional] Connection flags.
-- @return (boolean or nil) True on success, or nil and an error message on failure.
-- @see socket.connect
function inet:connect(addr, port, flags)
	self.socket:connect(net.aton(addr), port, flags)
end

---
-- Internal helper function to get socket address information.
-- @param what (string) Either "sockname" or "peername".
-- @return (string) IP address in string format.
-- @return (number) Port number.
-- @local
-- @see socket.getsockname
-- @see socket.getpeername
-- @see net.ntoa
function inet:getaddr(what)
	local socket = self.socket
	local ip, port = socket['get' .. what](socket)
	return net.ntoa(ip), port
end

---
-- Gets the local address (IP and port) to which the socket is bound.
-- @return (string) Local IP address.
-- @return (number) Local port number.
-- @see socket.getsockname
function inet:getsockname()
	return self:getaddr("sockname")
end

---
-- Gets the remote address (IP and port) to which the socket is connected.
-- @return (string) Remote IP address.
-- @return (number) Remote port number.
-- @see socket.getpeername
function inet:getpeername()
	return self:getaddr("peername")
end

local sock, ipproto = socket.sock, socket.ipproto

---
-- TCP socket specialization.
-- Provides methods specific to TCP sockets (e.g., `listen`, `accept`).
-- Create TCP sockets using `inet.tcp()`.
-- @table inet.tcp
-- @field type The socket type (e.g., `socket.sock.STREAM`).
-- @field proto The protocol (e.g., `socket.ipproto.TCP`).
inet.tcp = inet:new{type = sock.STREAM, proto = ipproto.TCP}

---
-- Listens for incoming connections on a TCP socket.
-- @param backlog (number) The maximum length of the queue of pending connections.
-- @return (boolean or nil) True on success, or nil and an error message on failure.
-- @see socket.listen
function inet.tcp:listen(backlog)
	self.socket:listen(backlog)
end

---
-- Accepts an incoming connection on a listening TCP socket.
-- @param flags (number) [optional] Flags for the accept operation.
-- @return (table or nil) A new socket object for the accepted connection, or nil and an error message.
-- @see socket.accept
function inet.tcp:accept(flags)
	return self.socket:accept(flags)
end

---
-- UDP socket specialization.
-- Provides methods specific to UDP sockets (e.g., `receivefrom`, `sendto`).
-- Create UDP sockets using `inet.udp()`.
-- @table inet.udp
-- @field type The socket type (e.g., `socket.sock.DGRAM`).
-- @field proto The protocol (e.g., `socket.ipproto.UDP`).
inet.udp = inet:new{type = sock.DGRAM, proto = ipproto.UDP}

---
-- Receives data from a UDP socket, along with the sender's address.
-- This is a wrapper around `inet:receive` that converts the raw IP address
-- from `net.aton` format to a string using `net.ntoa`.
-- @param len (number) [optional] The maximum number of bytes to receive.
-- @param flags (number) [optional] Flags for the receive operation.
-- @return (string or nil) The received data, or nil on error.
-- @return (string or nil) The sender's IP address, or an error message.
-- @return (number or nil) The sender's port number.
-- @see socket.receive
function inet.udp:receivefrom(len, flags)
	local msg, ip, port = self:receive(len, flags, true)
	return msg, net.ntoa(ip), port
end

---
-- Alias for `inet.udp:send`. Sends data to a specific address and port using UDP.
-- @function inet.udp:sendto
-- @param msg (string) The message to send.
-- @param addr (string) The destination IP address.
-- @param port (number) The destination port.
-- @return (boolean or nil) True on success, or nil and an error message on failure.
-- @see inet.send
-- @see socket.send
inet.udp.sendto = inet.udp.send -- Alias for send

return inet

