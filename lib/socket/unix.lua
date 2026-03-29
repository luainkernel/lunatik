--- UNIX domain (AF_UNIX) socket operations.
-- @module socket.unix
-- @see socket
-- @see socket.inet

local socket = require("socket")

local af   = socket.af
local sock = socket.sock

--- @type unix
local unix = {}

--- Socket constructor.
-- @param o [opt] Initial table.
-- @return New unix socket object.
function unix:new(o)
	local o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

--- Metamethod for instance creation (e.g. `unix.stream(path)`).
-- @tparam[opt] string path Default socket path.
-- @return New socket object.
-- @see socket.new
function unix:__call(path)
	local o = self:new{path = path}
	o.socket = socket.new(af.UNIX, self.type, 0)
	return o
end

--- Closes the socket.
-- @see socket.close
function unix:close()
	self.socket:close()
end

--- Binds the socket.
-- @tparam[opt] string path Path to bind to (defaults to stored path).
-- @see socket.bind
function unix:bind(path)
	self.socket:bind(path or self.path)
end

--- Connects the socket.
-- @tparam[opt] string path Path to connect to (defaults to stored path).
-- @see socket.connect
function unix:connect(path)
	self.socket:connect(path or self.path)
end

--- Sends data.
-- @tparam string msg Message to send.
-- @tparam[opt] string path Destination path.
-- @treturn number Bytes sent.
-- @see socket.send
function unix:send(msg, path)
	return path and self.socket:send(msg, path) or self.socket:send(msg)
end

--- Receives data.
-- @param ... Varargs for `socket:receive()`.
-- @see socket.receive
function unix:receive(...)
	return self.socket:receive(...)
end

--- Gets local path.
-- @return Local path.
-- @see socket.getsockname
function unix:getsockname()
	return self.socket:getsockname()
end

--- Gets remote path.
-- @return Remote path.
-- @see socket.getpeername
function unix:getpeername()
	return self.socket:getpeername()
end

--- STREAM specialization.
-- @table unix.stream
-- @field type `socket.sock.STREAM`
unix.stream = unix:new{type = sock.STREAM}

--- Listens for connections (STREAM).
-- @tparam number backlog Queue length.
-- @see socket.listen
function unix.stream:listen(backlog)
	self.socket:listen(backlog)
end

--- Accepts a connection (STREAM).
-- @tparam[opt] number flags Accept flags.
-- @return New socket object.
-- @see socket.accept
function unix.stream:accept(flags)
	return self.socket:accept(flags)
end

--- DGRAM specialization.
-- @table unix.dgram
-- @field type `socket.sock.DGRAM`
unix.dgram = unix:new{type = sock.DGRAM}

--- Receives data and sender's path (DGRAM).
-- @tparam[opt] number len Max length.
-- @tparam[opt] number flags Receive flags.
-- @return Data and path.
-- @see socket.receive
function unix.dgram:receivefrom(len, flags)
	return self:receive(len, flags, true)
end

--- Sends data to a path (DGRAM).
-- @tparam string msg Message to send.
-- @tparam[opt] string path Destination path (defaults to stored path).
-- @treturn number Bytes sent.
-- @see unix.send
function unix.dgram:sendto(msg, path)
	local dest = path or self.path
	return dest and self.socket:send(msg, dest) or self.socket:send(msg)
end

return unix

