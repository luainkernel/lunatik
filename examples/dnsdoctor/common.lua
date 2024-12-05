--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Common code for new netfilter framework and legacy iptables dns doctoring example

local nf = require("netfilter")
local linux = require("linux")
local action = nf.action
local dns = 0x35

local common = {}

local function get_domain(skb, off)
	local _, nameoff, name = skb:getstring(off):find("([^\0]*)")
	return name, nameoff + 1
end

function common.hook(skb, thoff, target_dns, target_ip, dst_ip)
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

return common
