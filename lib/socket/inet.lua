--- Internet (AF_INET) socket operations.
-- @module socket.inet
-- @see socket

local socket = require("socket")
local net = require("net")

--- @type inet
-- @field localhost The loopback address '127.0.0.1'.
local inet = {localhost = '127.0.0.1'}

--- Socket constructor.
-- @param o [opt] Initial table.
-- @return New inet socket object.
function inet:new(o)
	local o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

local af = socket.af
--- Metamethod for instance creation (e.g., `inet.tcp()`).
-- @return New socket object.
-- @see socket.new
-- @usage local tcp = inet.tcp()
function inet:__call()
	local o = self:new()
	o.socket = socket.new(af.INET, self.type, self.proto)
	return o
end

--- Closes the socket.
-- @see socket.close
function inet:close()
	self.socket:close()
end

--- Receives data.
-- @param ... Varargs for `socket:receive()`.
-- @return Data and address info.
-- @see socket.receive
function inet:receive(...)
	return self.socket:receive(...)
end

--- Sends data.
-- @tparam string msg Message to send.
-- @tparam[opt] string addr Destination address (for UDP).
-- @tparam[opt] number port Destination port (for UDP).
-- @treturn number Bytes sent.
-- @see socket.send
function inet:send(msg, addr, port)
	local sock = self.socket
	return not addr and sock:send(msg) or sock:send(msg, net.aton(addr), port)
end

--- Binds the socket.
-- @tparam string addr IP address ('*' for any).
-- @tparam number port Port number.
-- @treturn boolean Success.
-- @see socket.bind
function inet:bind(addr, port)
	local ip = addr ~= '*' and net.aton(addr) or 0
	return self.socket:bind(ip, port)
end

--- Connects the socket.
-- @tparam string addr Remote IP address.
-- @tparam number port Remote port.
-- @tparam[opt] number flags Connection flags.
-- @see socket.connect
function inet:connect(addr, port, flags)
	self.socket:connect(net.aton(addr), port, flags)
end

--- Internal helper for address info.
-- @local
function inet:getaddr(what)
	local socket = self.socket
	local ip, port = socket['get' .. what](socket)
	return net.ntoa(ip), port
end

--- Gets local bound address.
-- @return IP and port.
-- @see socket.getsockname
function inet:getsockname()
	return self:getaddr("sockname")
end

--- Gets remote connected address.
-- @return IP and port.
-- @see socket.getpeername
function inet:getpeername()
	return self:getaddr("peername")
end

local sock, ipproto = socket.sock, socket.ipproto

--- TCP specialization.
-- @table inet.tcp
-- @field type `socket.sock.STREAM`
-- @field proto `socket.ipproto.TCP`
inet.tcp = inet:new{type = sock.STREAM, proto = ipproto.TCP}

--- Listens for connections (TCP).
-- @tparam number backlog Queue length.
-- @see socket.listen
function inet.tcp:listen(backlog)
	self.socket:listen(backlog)
end

--- Accepts a connection (TCP).
-- @tparam[opt] number flags Accept flags.
-- @return New socket object.
-- @see socket.accept
function inet.tcp:accept(flags)
	return self.socket:accept(flags)
end

--- UDP specialization.
-- @table inet.udp
-- @field type `socket.sock.DGRAM`
-- @field proto `socket.ipproto.UDP`
inet.udp = inet:new{type = sock.DGRAM, proto = ipproto.UDP}

--- Receives data and sender's address (UDP).
-- @tparam[opt] number len Max length.
-- @tparam[opt] number flags Receive flags.
-- @return Data, IP, and port.
-- @see socket.receive
function inet.udp:receivefrom(len, flags)
	local msg, ip, port = self:receive(len, flags, true)
	return msg, net.ntoa(ip), port
end

--- Alias for `send`.
-- @function inet.udp:sendto
inet.udp.sendto = inet.udp.send

return inet

