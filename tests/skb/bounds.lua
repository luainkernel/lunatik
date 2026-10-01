--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the skb bounds test (see bounds.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local ipproto   = require("linux.socket").ipproto

local IP_PROTO    <const> = 9
local UDP_DPORT   <const> = 2
local PORT        <const> = 5566
local U32_MAX     <const> = 0xffffffff
local KEPT        <const> = 0x5a5a
local OUTOFBOUNDS <const> = "out of bounds"

local accessors <const> = {"mark", "priority"}
local accepted  <const> = {0, U32_MAX}
local refused   <const> = {-1, U32_MAX + 1, (1 << 32) | KEPT}

local done = false

local function refusal(skb, accessor, value)
	local ok, err = pcall(skb[accessor], skb, value)
	local held = skb[accessor](skb)
	if ok then
		return "FAIL accepted " .. value
	elseif not err:find(OUTOFBOUNDS, 1, true) then
		return "FAIL raised " .. err
	elseif held ~= KEPT then
		return "FAIL refusing " .. value .. " left " .. held
	end
end

local function check(skb, accessor)
	for _, value in ipairs(accepted) do
		local got = skb[accessor](skb, value)
		if got ~= value then
			return "FAIL took " .. value .. " as " .. got
		end
	end
	skb[accessor](skb, KEPT)
	for _, value in ipairs(refused) do
		local failure = refusal(skb, accessor, value)
		if failure ~= nil then
			return failure
		end
	end
	return "ok"
end

local function bounds_hook(skb)
	local pkt = skb:data()
	if done or pkt:getuint8(IP_PROTO) ~= ipproto.UDP then
		return nf.action.ACCEPT
	end
	local ihl = (pkt:getuint8(0) & 0x0F) * 4
	if byteorder.ntoh16(pkt:getuint16(ihl + UDP_DPORT)) == PORT then
		done = true
		for _, accessor in ipairs(accessors) do
			print("skb bounds: " .. accessor .. " " .. check(skb, accessor))
		end
	end
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = bounds_hook,
	pf       = nf.proto.IPV4,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

