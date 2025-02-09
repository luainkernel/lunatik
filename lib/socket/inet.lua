--
-- SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only 
--

local socket = require("socket")
local net = require("net")

local inet = {localhost = '127.0.0.1'}

function inet:new(o)
	local o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

local af = socket.af
function inet:__call()
	local o = self:new()
	o.socket = socket.new(af.INET, self.type, self.proto)
	return o
end

function inet:close()
	self.socket:close()
end

function inet:receive(...)
	return self.socket:receive(...)
end

function inet:send(msg, addr, port)
	local sock = self.socket
	return not addr and sock:send(msg) or sock:send(msg, net.aton(addr), port)
end

function inet:bind(addr, port)
	local ip = addr ~= '*' and net.aton(addr) or 0
	return self.socket:bind(ip, port)
end

function inet:connect(addr, port, flags)
	self.socket:connect(net.aton(addr), port, flags)
end

function inet:getaddr(what)
	local socket = self.socket
	local ip, port = socket['get' .. what](socket)
	return net.ntoa(ip), port
end

function inet:getsockname()
	return self:getaddr("sockname")
end

function inet:getpeername()
	return self:getaddr("peername")
end

local sock, ipproto = socket.sock, socket.ipproto

inet.tcp = inet:new{type = sock.STREAM, proto = ipproto.TCP}

function inet.tcp:listen(backlog)
	self.socket:listen(backlog)
end

function inet.tcp:accept(flags)
	return self.socket:accept(flags)
end

inet.udp = inet:new{type = sock.DGRAM, proto = ipproto.UDP}

function inet.udp:receivefrom(len, flags)
	local msg, ip, port = self:receive(len, flags, true)
	return msg, net.ntoa(ip), port
end

inet.udp.sendto = inet.udp.send

return inet

