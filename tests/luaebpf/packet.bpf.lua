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

function makers.getbyte(keep) return function(ctx) local p = ctx:packet() local v = p:getbyte(AT) keep(v) end end
function makers.getuint8(keep) return function(ctx) local p = ctx:packet() local v = p:getuint8(AT) keep(v) end end
function makers.getint8(keep) return function(ctx) local p = ctx:packet() local v = p:getint8(AT) keep(v) end end
function makers.getuint16(keep) return function(ctx) local p = ctx:packet() local v = p:getuint16(AT) keep(v) end end
function makers.getint16(keep) return function(ctx) local p = ctx:packet() local v = p:getint16(AT) keep(v) end end
function makers.getuint32(keep) return function(ctx) local p = ctx:packet() local v = p:getuint32(AT) keep(v) end end
function makers.getint32(keep) return function(ctx) local p = ctx:packet() local v = p:getint32(AT) keep(v) end end
function makers.getint64(keep) return function(ctx) local p = ctx:packet() local v = p:getint64(AT) keep(v) end end
function makers.length(keep) return function(ctx) local p = ctx:packet() keep(#p) end end
function makers.called(keep) return function(ctx) local p = ctx:packet() local v = u16(p, AT) keep(v) end end

function skbmakers.getbyte(keep) return function(skb) local p = skb:data() local v = p:getbyte(AT) keep(v) end end
function skbmakers.getuint8(keep) return function(skb) local p = skb:data() local v = p:getuint8(AT) keep(v) end end
function skbmakers.getint8(keep) return function(skb) local p = skb:data() local v = p:getint8(AT) keep(v) end end
function skbmakers.getuint16(keep) return function(skb) local p = skb:data() local v = p:getuint16(AT) keep(v) end end
function skbmakers.getint16(keep) return function(skb) local p = skb:data() local v = p:getint16(AT) keep(v) end end
function skbmakers.getuint32(keep) return function(skb) local p = skb:data() local v = p:getuint32(AT) keep(v) end end
function skbmakers.getint32(keep) return function(skb) local p = skb:data() local v = p:getint32(AT) keep(v) end end
function skbmakers.getint64(keep) return function(skb) local p = skb:data() local v = p:getint64(AT) keep(v) end end
function skbmakers.length(keep) return function(skb) local p = skb:data() keep(#p) end end
function skbmakers.called(keep) return function(skb) local p = skb:data() local v = u16(p, AT) keep(v) end end

-- an accessor asked for two results, where Lua fills the second with nil: the row answers the
-- fill on both sides, and the read itself where the second result kept the receiver's type
function makers.oneresult(keep)
	return function(ctx)
		local p = ctx:packet()
		local v, w = p:getbyte(AT)
		if w == nil then
			v = FILLED
		end
		keep(v)
	end
end

function skbmakers.oneresult(keep)
	return function(skb)
		local p = skb:data()
		local v, w = p:getbyte(AT)
		if w == nil then
			v = FILLED
		end
		keep(v)
	end
end

-- the offset comes from an earlier read, so the bound on a computed offset is exercised too
function makers.computed(keep)
	return function(ctx)
		local p = ctx:packet()
		local ihl = (p:getbyte(IHL) & 0x0f) * 4
		local v = p:getbyte(IHL + ihl)
		keep(v)
	end
end

function skbmakers.computed(keep)
	return function(skb)
		local p = skb:data()
		local ihl = (p:getbyte(IHL) & 0x0f) * 4
		local v = p:getbyte(IHL + ihl)
		keep(v)
	end
end

local order = {"getbyte", "getuint8", "getint8", "getuint16", "getint16", "getuint32",
	"getint32", "getint64", "length", "called", "computed", "oneresult"}

local contexts, skbcontexts = corpus.packets(), corpus.skbpackets()

-- every row over each packet twice, through ctx:packet() and through skb:data()
local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:stores(op .. i, makers[op], nil, contexts[name])
		rows:stores("skb" .. op .. i, skbmakers[op], nil, skbcontexts[name])
	end
end
rows:close()

