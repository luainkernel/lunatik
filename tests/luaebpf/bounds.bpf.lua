--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the bounds case (see bounds.sh).

local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp").action
local tc      = require("linux.tc").action

local CEILING <const> = 70000 -- above the last offset the verifier lets a packet pointer take
local DEEP    <const> = 120   -- inside the whole ClientHello's SNI, past the truncated one
local BELOW   <const> = 256   -- past what a byte holds, so a byte less this is a negative offset

-- each row over the packet as each program type opens it: ctx:packet() on XDP and skb:data() on TC
local makers, skbmakers = {}, {}

-- one byte past the last, which the interpreter raises on and the bounds check refuses
function makers.past() return function(ctx) local p = ctx:packet() local v = p:getbyte(#p) return v end end
function makers.high() return function(ctx) local p = ctx:packet() local v = p:getbyte(CEILING) return v end end
function makers.deep() return function(ctx) local p = ctx:packet() local v = p:getuint16(DEEP) return v end end
-- an offset the program computes below the packet, which the interpreter raises on too
function makers.negative()
	return function(ctx) local p = ctx:packet() local v = p:getbyte(p:getbyte(0) - BELOW) return v end
end

function skbmakers.past() return function(skb) local p = skb:data() local v = p:getbyte(#p) return v end end
function skbmakers.high() return function(skb) local p = skb:data() local v = p:getbyte(CEILING) return v end end
function skbmakers.deep() return function(skb) local p = skb:data() local v = p:getuint16(DEEP) return v end end
function skbmakers.negative()
	return function(skb) local p = skb:data() local v = p:getbyte(p:getbyte(0) - BELOW) return v end
end

local order = {"past", "high", "deep", "negative"}

local contexts, skbcontexts = corpus.packets(), corpus.skbpackets()

-- each row twice, under either default, so the answer is the verdict the file asked for rather
-- than a number the failure path happens to leave behind
local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op](), action.DROP, contexts[name])
		rows:declare(op .. "pass" .. i, makers[op](), action.PASS, contexts[name])
		rows:declare("skb" .. op .. i, skbmakers[op](), tc.SHOT, skbcontexts[name])
		rows:declare("skb" .. op .. "ok" .. i, skbmakers[op](), tc.OK, skbcontexts[name])
	end
end
rows:close()

