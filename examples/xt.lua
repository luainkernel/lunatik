--
-- Copyright (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
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

-- Match DNS packets using netfilter match

local xt = require("xtable")
local linux = require("linux")
local action = xt.action
local family = xt.family

local udp = 0x11
local dns = 0x35

local function nop() end

local function match_packet(skb)
	print("match_packet called\n")
	-- ip header
	local ipb = skb:getuint8(0)
	local ihlen = ((ipb << 4 ) & 0xFF) >> 4
	local iphdrlen = ihlen * 4
	local proto = skb:getuint8(9)

	if proto == udp then
		local srcport = linux.ntoh16(skb:getuint16(iphdrlen))
		local dstport = linux.ntoh16(skb:getuint16(iphdrlen + 2))
		if srcport == dns or dstport == dns then
			print("DNS packet\n")
			return action.ACCEPT
		end
	end

	return action.DROP
end

local match_ops = {
	name= "luaxtabletest",
	revision=1,
	family= family.UNSPEC,
	proto=0,
	match= match_packet,
	checkentry=nop,
	destroy=nop,
}

xt.match(match_ops)

