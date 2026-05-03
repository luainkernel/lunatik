--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp    = require("xdp")
local action = require("linux.xdp")

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
		local offset = base + offset
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

local function filter_sni(ctx)
	local packet   = ctx:packet()
	local argument = ctx:argument()

	local byte, short, str = unpacker(packet, offset(argument))

	if byte(0) ~= handshake or byte(5) ~= client_hello then
		ctx:set_action(action.PASS)
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

			verdict = blacklist[sni] and "DROP" or "PASS"
			log(sni, verdict)
			ctx:set_action(action[verdict])
			return
		end
		extension = data + short(extension + 2)
	end

	ctx:set_action(action.PASS)
end

xdp.attach(filter_sni)
