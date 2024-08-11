--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring : Rewrite DNS type A record to a private address for local clients

local xt = require("xtable")
local linux = require("linux")
local string = require("string")
local action = xt.action
local family = xt.family

local udp = 0x11
local dns = 0x35

local function nop() end

local function get_domain(skb, off)
	local _, nameoff, name = skb:getstring(off):find("([^\0]*)")
	return name, nameoff + 1
end

local function dnsdoctor_tg(skb, par, userargs)
	local target_dns, dst_ip, target_ip = string.unpack(">s4I4I4", userargs)
	local thoff = par.thoff

	local packetdst = skb:getuint32(16)
	if packetdst ~= linux.hton32(dst_ip) then
		return action.ACCEPT
	end

	local srcport = linux.ntoh16(skb:getuint16(thoff))
	if srcport == dns then
		local dnsoff = thoff + 8
		local nanswers = linux.ntoh16(skb:getuint16(dnsoff + 6))

		-- check the domain name
		dnsoff = dnsoff + 12
		local domainname, nameoff = get_domain(skb, dnsoff)

		if domainname == target_dns then
			dnsoff = dnsoff + nameoff + 4 -- skip over type, label fields
			-- iterate over answers
			for i = 1, nanswers do
				local atype = linux.hton16(skb:getuint16(dnsoff + 2))
				if atype == 1 then
					skb:setuint32(dnsoff + 12, linux.hton32(target_ip))
				end
				dnsoff = dnsoff + 16
			end
		end
	end

	return action.ACCEPT
end

xt.target{
	name = "dnsdoctor",
	revision = 0,
	family = family.UNSPEC,
	proto = 0,
	target = dnsdoctor_tg,
	checkentry = nop,
	destroy = nop,
	hooks = 0,
}

