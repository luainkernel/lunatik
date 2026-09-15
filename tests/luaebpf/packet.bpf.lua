-- see packet.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")

local AT      <const> = 6  -- the source address, whose first byte has its high bit set
local IHL     <const> = 14 -- the IPv4 header's first byte, where its length in words lives
local FILLED  <const> = 11 -- the answer a row owes when the second result of a call is nil
local IFINDEX <const> = 1
local QUEUE   <const> = 0

-- examples/common/sni.lua's helper, unchanged: the proxy passes to a subprogram in one argument
local function u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

local makers = {}

function makers.getbyte() return function(ctx) local p = ctx:packet() local v = p:getbyte(AT) return v end end
function makers.getuint8() return function(ctx) local p = ctx:packet() local v = p:getuint8(AT) return v end end
function makers.getint8() return function(ctx) local p = ctx:packet() local v = p:getint8(AT) return v end end
function makers.getuint16() return function(ctx) local p = ctx:packet() local v = p:getuint16(AT) return v end end
function makers.getint16() return function(ctx) local p = ctx:packet() local v = p:getint16(AT) return v end end
function makers.getuint32() return function(ctx) local p = ctx:packet() local v = p:getuint32(AT) return v end end
function makers.getint32() return function(ctx) local p = ctx:packet() local v = p:getint32(AT) return v end end
function makers.getint64() return function(ctx) local p = ctx:packet() local v = p:getint64(AT) return v end end
function makers.getnumber() return function(ctx) local p = ctx:packet() local v = p:getnumber(AT) return v end end
function makers.length() return function(ctx) local p = ctx:packet() return #p end end
function makers.called() return function(ctx) local p = ctx:packet() local v = u16(p, AT) return v end end

-- an accessor asked for two results, where Lua fills the second with nil: the row answers the
-- fill on both sides, and the read itself where the second result kept the receiver's type
function makers.oneresult()
	return function(ctx)
		local p = ctx:packet()
		local v, w = p:getbyte(AT)
		if w == nil then
			return FILLED
		end
		return v
	end
end

-- the offset comes from an earlier read, so the bound on a computed offset is exercised too
function makers.computed()
	return function(ctx)
		local p = ctx:packet()
		local ihl = (p:getbyte(IHL) & 0x0f) * 4
		local v = p:getbyte(IHL + ihl)
		return v
	end
end

local order = {"getbyte", "getuint8", "getint8", "getuint16", "getint16", "getuint32",
	"getint32", "getint64", "getnumber", "length", "called", "computed", "oneresult"}

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op](), nil, contexts[name])
	end
end
rows:close()

