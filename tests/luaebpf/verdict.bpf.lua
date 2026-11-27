--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the verdict case (see verdict.sh).

local corpus = require("tests.luaebpf.corpus")
local xdp    = require("bpf.xdp")
local tc     = require("bpf.tc")
local action = require("linux.xdp").action
local tcact  = require("linux.tc").action

-- an ethertype no IP header follows: an skb test run refuses an IPv4 one whose header is missing
local FRAME <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x88\xb5"
local WORD  <const> = 32 -- the bits of a verdict the kernel reads
local PAST  <const> = 20 -- past the fourteen bytes of either frame

-- the XDP rows read the fourteen bytes common.sh hands prog run, whose byte 12 is 8 and byte 13 is
-- 0; the TC rows read FRAME, whose byte 6 is 0 and byte 7 is 0x11
local function above(n)
	return n - 3
end

local function xdpfirst(ctx) local p = ctx:packet() local v = p:getbyte(13) return v end
local function xdplast(ctx) local p = ctx:packet() local v = p:getbyte(12) - 4 return v end
local function xdpabove(ctx) local p = ctx:packet() local v = p:getbyte(12) - 3 return v end
local function xdpbelow(ctx) local p = ctx:packet() local v = p:getbyte(13) - 1 return v end
-- past 32 bits, over the low half XDP_PASS: the kernel reads the low half
local function xdphigh(ctx) local p = ctx:packet() local v = p:getbyte(12) << WORD | action.PASS return v end
local function xdpcalled(ctx) local p = ctx:packet() local n = p:getbyte(12) local v = above(n) return v end

local function tcfirst(skb) local p = skb:data() local v = p:getbyte(6) - 1 return v end
local function tclast(skb) local p = skb:data() local v = p:getbyte(7) - 9 return v end
local function tcabove(skb) local p = skb:data() local v = p:getbyte(7) - 8 return v end
local function tcbelow(skb) local p = skb:data() local v = p:getbyte(6) - 2 return v end
local function tchigh(skb) local p = skb:data() local v = p:getbyte(7) << WORD | tcact.OK return v end
local function tccalled(skb) local p = skb:data() local n = p:getbyte(7) local v = above(n) return v end
local function tcunspec(_) return tcact.UNSPEC end
local function tctrap(_) return tcact.TRAP end
local function idle(_) end

-- each reads past the fourteen bytes of its frame; a read that kept 0 rather than stopping returns TX
-- or PIPE, which none of the programs below owes
local function xdpshort(ctx) local p = ctx:packet() if p:getbyte(PAST) == 0 then return action.TX end end
local function tcshort(skb) local p = skb:data() if p:getbyte(PAST) == 0 then return tcact.PIPE end end
local function past(p) local v = p:getbyte(PAST) return v end
local function xdpcallee(ctx) local p = ctx:packet() if past(p) == 0 then return action.TX end end
local function tccallee(skb) local p = skb:data() if past(p) == 0 then return tcact.PIPE end end

for _, program in ipairs({{"xdpfirst", xdpfirst}, {"xdplast", xdplast}, {"xdpabove", xdpabove},
		{"xdpbelow", xdpbelow}, {"xdphigh", xdphigh}, {"xdpcalled", xdpcalled}}) do
	xdp.program(program[2], {name = program[1], default = action.DROP})
end
for _, program in ipairs({{"tcfirst", tcfirst}, {"tclast", tclast}, {"tcabove", tcabove},
		{"tcbelow", tcbelow}, {"tchigh", tchigh}, {"tccalled", tccalled}, {"tcunspec", tcunspec},
		{"tctrap", tctrap}}) do
	tc.program(program[2], {name = program[1], default = tcact.OK})
end
for _, program in ipairs({{"xdperror", xdpshort, action.PASS}, {"xdpnoerror", xdpshort},
		{"xdpcalleeerror", xdpcallee, action.REDIRECT}, {"xdpcalleenone", xdpcallee},
		{"xdpnostop", idle, action.PASS}}) do
	xdp.program(program[2], {name = program[1], default = action.DROP, error = program[3]})
end
for _, program in ipairs({{"tcerror", tcshort, tcact.OK}, {"tcnoerror", tcshort},
		{"tccalleeerror", tccallee, tcact.TRAP}, {"tccalleenone", tccallee}, {"tcnostop", idle, tcact.OK}}) do
	tc.program(program[2], {name = program[1], default = tcact.UNSPEC, error = program[3]})
end

corpus.context("tcframe", "__sk_buff", {}, FRAME)

