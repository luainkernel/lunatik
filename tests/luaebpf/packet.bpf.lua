--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the packet case (see packet.sh).

local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")

local AT      <const> = 6  -- the source address, whose first byte has its high bit set
local IHL     <const> = 14 -- the IPv4 header's first byte, where its length in words lives
local FILLED  <const> = 11 -- the answer a row owes when the second result of a call is nil

-- examples/common/sni.lua's helper, unchanged: the proxy passes to a subprogram in one argument
local function u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

-- each row twice, over the packet as each program type opens it: ctx:packet() on XDP and
-- skb:data() on TC, the kernel objects' own names, which a compiled method call carries as written
local makers, skbmakers = {}, {}

function makers.getbyte() return function(ctx) local p = ctx:packet() local v = p:getbyte(AT) return v end end
function makers.getuint8() return function(ctx) local p = ctx:packet() local v = p:getuint8(AT) return v end end
function makers.getint8() return function(ctx) local p = ctx:packet() local v = p:getint8(AT) return v end end
function makers.getuint16() return function(ctx) local p = ctx:packet() local v = p:getuint16(AT) return v end end
function makers.getint16() return function(ctx) local p = ctx:packet() local v = p:getint16(AT) return v end end
function makers.getuint32() return function(ctx) local p = ctx:packet() local v = p:getuint32(AT) return v end end
function makers.getint32() return function(ctx) local p = ctx:packet() local v = p:getint32(AT) return v end end
function makers.getint64() return function(ctx) local p = ctx:packet() local v = p:getint64(AT) return v end end
function makers.length() return function(ctx) local p = ctx:packet() return #p end end
function makers.called() return function(ctx) local p = ctx:packet() local v = u16(p, AT) return v end end

function skbmakers.getbyte() return function(skb) local p = skb:data() local v = p:getbyte(AT) return v end end
function skbmakers.getuint8() return function(skb) local p = skb:data() local v = p:getuint8(AT) return v end end
function skbmakers.getint8() return function(skb) local p = skb:data() local v = p:getint8(AT) return v end end
function skbmakers.getuint16() return function(skb) local p = skb:data() local v = p:getuint16(AT) return v end end
function skbmakers.getint16() return function(skb) local p = skb:data() local v = p:getint16(AT) return v end end
function skbmakers.getuint32() return function(skb) local p = skb:data() local v = p:getuint32(AT) return v end end
function skbmakers.getint32() return function(skb) local p = skb:data() local v = p:getint32(AT) return v end end
function skbmakers.getint64() return function(skb) local p = skb:data() local v = p:getint64(AT) return v end end
function skbmakers.length() return function(skb) local p = skb:data() return #p end end
function skbmakers.called() return function(skb) local p = skb:data() local v = u16(p, AT) return v end end

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

function skbmakers.oneresult()
	return function(skb)
		local p = skb:data()
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

function skbmakers.computed()
	return function(skb)
		local p = skb:data()
		local ihl = (p:getbyte(IHL) & 0x0f) * 4
		local v = p:getbyte(IHL + ihl)
		return v
	end
end

local order = {"getbyte", "getuint8", "getint8", "getuint16", "getint16", "getuint32",
	"getint32", "getint64", "length", "called", "computed", "oneresult"}

local contexts, skbcontexts = corpus.packets(), corpus.skbpackets()

-- every row over each packet twice, through ctx:packet() and through skb:data()
local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op](), nil, contexts[name])
		rows:declare("skb" .. op .. i, skbmakers[op](), nil, skbcontexts[name])
	end
end
rows:close()

