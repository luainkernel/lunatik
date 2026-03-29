--- RAW AF_PACKET socket operations.
-- @module socket.raw
-- @see socket

local socket = require("socket")
local eth    = require("linux.eth")

local af   = socket.af
local sock = socket.sock

local raw = {}

--- Creates and binds a raw packet socket.
-- @tparam[opt] number proto EtherType (defaults to `eth.ALL`).
-- @tparam[opt] number ifindex Interface index (defaults to 0, all interfaces).
-- @return New raw socket.
-- @usage local rx = raw.bind(0x0003)
-- @see socket.new
-- @see socket.bind
function raw.bind(proto, ifindex)
	local proto = proto or eth.ALL
	local ifindex = ifindex or 0
	local s = socket.new(af.PACKET, sock.RAW, proto)
	s:bind(proto, ifindex)
	return s
end

return raw

