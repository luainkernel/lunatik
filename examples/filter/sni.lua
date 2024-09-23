--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp  = require("xdp")
local netfilter = require("netfilter")

local function set(t)
	local s = {}
	for _, key in ipairs(t) do s[key] = true end
	return s
end

local blacklist = set{
	"ebpf.io",
}

local function log(sni, verdict)
	print(string.format("filter_sni: %s %s", sni, verdict))
end

local function unpacker(packet, base)
	local byte = function (offset)
		return packet:getbyte(base + offset)
	end

	local short = function (offset)
		offset = base + offset
		return packet:getbyte(offset) << 8 | packet:getbyte(offset + 1)
	end

	local str = function (offset, length)
		return packet:getstring(base + offset, length)
	end

	return byte, short, str
end

local function offset(argument)
	return select(2, unpacker(argument, 0))(0)
end

local client_hello = 0x01
local handshake    = 0x16
local server_name  = 0x00

local session = 43
local max_extensions = 17

local function filter_sni(packet, argument)  -- argument will get passed only with XDP
	local action = {}
	local _offset
	if tonumber(argument) then  -- XDP case
		action = xdp.action
		_offset = argument
	else  -- netfilter case
		for k, v in pairs(netfilter.action) do  -- we make a copy to avoid adding "PASS" directly onto netfilter.action
			action[k] = v
		end
		action.PASS = action.CONTINUE  -- could be set to action.ACCEPT to bypass subsequent rules
		local first_byte = packet:getbyte(0)
		local ip_version = first_byte >> 4
		_offset = ({
			[6] = 40,
			[4] = (first_byte & 0xf)
		})[ip_version]
	end

	local byte, short, str = unpacker(packet, offset(_offset))

	if byte(0) ~= handshake or byte(5) ~= client_hello then
		return action.PASS
	end

	local cipher = (session + 1) + byte(session)
	local compression = cipher + 2 + short(cipher)
	local extension = compression + 3 + byte(compression)

	for i = 1, max_extensions do
		local data = extension + 4
		if short(extension) == server_name then
			local length = short(data + 3)
			local sni = str(data + 5, length)

			local verdict = blacklist[sni] and "DROP" or "PASS"
			log(sni, verdict)
			return action[verdict]
		end
		extension = data + short(extension + 2)
	end

	return action.PASS
end

xdp.attach(filter_sni)

-- In case of bridged networking
netfilter.register{
	pf = netfilter.family.BRIDGE,
	hooknum = netfilter.bridge_hooks.FORWARD,
	priority = netfilter.bridge_priority.FILTER_BRIDGED,
	hook = filter_sni
}

-- In case of a router
for _, pf in ipairs{netfilter.family.IPV4, netfilter.family.IPV6} do
	netfilter.register{
		pf = pf,
		hooknum = netfilter.inet_hooks.FORWARD,
		priority = netfilter.ip_priority.FILTER,
		hook = filter_sni
	}
end

