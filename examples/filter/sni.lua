--
-- SPDX-FileCopyrightText: (c) 2024-2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp = require("xdp")
local linux = require("linux")

local action = xdp.action

local ntoh16, ntoh32 = linux.ntoh16, linux.ntoh32

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
	base = base or 0

	local u8 = function (offset)
		return packet:getuint8(base + offset)
	end

	local be16 = function (offset)
		return ntoh16(packet:getuint16(base + offset))
	end

	local be32 = function (offset)
		return ntoh32(packet:getuint32(base + offset))
	end

	local str = function (offset, length)
		return packet:getstring(base + offset, length)
	end

	return str, u8, be16, be32
end

local function argparser(argument)
	local _, _, be16, be32 = unpacker(argument)
	local offset = be16(0)
	local conn = string.format("%X:%X:%X", be16(2), be32(4), be32(10))
	return offset, conn
end

local client_hello = 0x01
local handshake    = 0x16
local server_name  = 0x00
local host_name    = 0x00

local session = 43
local max_extensions = 17

function segment(packet, offset)
	local str, u8, be16 = unpacker(packet, offset)

	local last = #packet - offset - 1
	for i = 0, last do
		local extension_type   = be16(i)
		local server_name_type = u8(i + 6)

		if extension_type == server_name and server_name_type == host_name then
			local extension_len        = be16(i + 2)
			local server_name_list_len = be16(i + 4)
			local server_name_len      = be16(i + 7)

			if extension_len == server_name_list_len + 2 and
			   extension_len == server_name_len + 5 then
				return str(i + 9, server_name_len)
			end
		end
	end
end

local pending = {}

local function filter_sni(packet, argument)
	local offset, conn = argparser(argument)

	if pending[conn] then
		pending[conn] = nil
		return segment(packet, offset)
	end

	local str, u8, be16 = unpacker(packet, offset)
	if u8(0) ~= handshake or u8(5) ~= client_hello then
		return action.PASS
	end

	pending[conn] = true

	local cipher = (session + 1) + u8(session)
	local compression = cipher + 2 + be16(cipher)
	local extension = compression + 3 + u8(compression)

	for i = 1, max_extensions do
		local data = extension + 4
		if be16(extension) == server_name then
			pending[conn] = nil

			local length = be16(data + 3)
			local sni = str(data + 5, length)

			verdict = blacklist[sni] and "DROP" or "PASS"
			log(sni, verdict)
			return action[verdict]
		end
		extension = data + be16(extension + 2)
	end

	pending[conn] = nil
	log("unknown", "PASS")
	return action.PASS
end

xdp.attach(filter_sni)

