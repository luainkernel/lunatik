--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local linux = require("linux")
local xdp   = require("xdp")
local nf    = require("netfilter")

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

local client_hello = 0x01
local handshake    = 0x16
local server_name  = 0x00

local session = 43
local max_extensions = 17

local function filter_sni(packet, offset)
	local byte, short, str = unpacker(packet, offset)

	if byte(0) ~= handshake or byte(5) ~= client_hello then
		return
	end

	local cipher = (session + 1) + byte(session)
	local compression = cipher + 2 + short(cipher)
	local extension = compression + 3 + byte(compression)

	for i = 1, max_extensions do
		local data = extension + 4
		if short(extension) == server_name then
			local length = short(data + 3)
			local sni = str(data + 5, length)

			local isblock = blacklist[sni]
			log(sni, isblock and "DROP" or "PASS/CONTINUE")
			return isblock
		end
		extension = data + short(extension + 2)
	end
end

xdp.attach(function (packet, argument)
	local offset = linux.ntoh16(argument:getuint16(0))
	local action = xdp.action
	return filter_sni(packet, offset) and action.DROP or action.PASS
end)

nf.register{
	pf = nf.family.INET,
	hooknum = nf.inet_hooks.FORWARD,
	priority = nf.ip_priority.LAST,
	hook = function (packet)
		local ihl = packet:getbyte(0) & 0x0F
		local thoff = ihl * 4
		local doff = ((packet:getbyte(thoff + 12) >> 4) & 0x0F) * 4
		local offset = thoff + doff
		local dport = linux.ntoh16(packet:getuint16(thoff + 2))
		local action = nf.action
		return (offset < #packet and dport == 443 and filter_sni(packet, offset))
			and action.DROP or action.CONTINUE
	end,
}

