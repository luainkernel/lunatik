--
-- Copyright (c) 2023 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

local socket = require("socket")

local inet = {localhost = '127.0.0.1'}

function inet.aton(addr)
	local i = 1
	local bits = {24, 16, 8, 0}
	local ip = 0
	for n in string.gmatch(addr, "(%d+)") do
		n = tonumber(n) & 0xFF
  		ip = ip | (n << bits[i])
  		i = i + 1
	end
	return ip
end

function inet.ntoa(ip)
	local n = 4
	local bytes = {}
	for i = 1, n do
		local shift = (n - i) * 8
		local mask = 0xFF << shift
		bytes[i] = (ip & mask) >> shift
	end
	return table.concat(bytes, '.')
end

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
	return not addr and sock:send(msg) or sock:send(msg, inet.aton(addr), port)
end

function inet:bind(addr, port)
	local ip = addr ~= '*' and inet.aton(addr) or 0
	return self.socket:bind(ip, port)
end

function inet:connect(addr, port, flags)
	self.socket:connect(inet.aton(addr), port, flags)
end

function inet:getaddr(what)
	local socket = self.socket
	local ip, port = socket['get' .. what](socket)
	return inet.ntoa(ip), port
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
	return msg, inet.ntoa(ip), port
end

inet.udp.sendto = inet.udp.send

return inet

