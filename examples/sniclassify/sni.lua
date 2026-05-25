--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Based on https://github.com/luainkernel/lunatik/blob/master/examples/filter/sni.lua

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")

local TC_H_MAKE = function(maj, min) return (maj << 16) | min end

local client_hello = 0x01
local handshake    = 0x16
local server_name  = 0x0000

local session = 43
local max_extensions = 17

local policy = {
	["netflix%.com"] = TC_H_MAKE(1, 20),
	["zoom%.com"]    = TC_H_MAKE(1, 10),
}

local function log(sni, priority)
	print(string.format("sniclassify: %s %s", sni, priority))
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

local function sniclassify(ctx)
	local argument = ctx:argument()
	local skb = skbattr(ctx:skb())
	local data = skb:data()
	local byte, short, str = unpacker(data, offset(argument))

	if byte(0) ~= handshake or byte(5) ~= client_hello then
		ctx:action(action.ACT_OK)
		return
	end

	local cipher      = (session + 1) + byte(session)
	local compression = cipher + 2 + short(cipher)
	local extension   = compression + 3 + byte(compression)

	for _ = 1, max_extensions do
		local data_off = extension + 4
		if short(extension) == server_name then
			local sni = str(data_off + 5, short(data_off + 3))
			for pattern, classid in pairs(policy) do
				if sni:match(pattern) then
					log(sni, classid)
					skb.priority = classid
					break
				end
			end
			ctx:action(action.ACT_OK)
			return
		end
		extension = data_off + short(extension + 2)
	end

	ctx:action(action.ACT_OK)
end

tc.attach(sniclassify)

