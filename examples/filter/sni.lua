--
-- Copyright (c) 2024 ring-0 Ltda.
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

local xdp  = require("xdp")
local data = require("data")

local action = xdp.action

local function set(t)
	local s = {}
	for _, key in ipairs(t) do s[key] = true end
	return s
end

local blacklist = set(require("examples/filter/blacklist"))

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

local function filter_sni(packet, argument)
	local byte, short, str = unpacker(packet, offset(argument))

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

			verdict = blacklist[sni] and "DROP" or "PASS"
			log(sni, verdict)
			return action[verdict]
		end
		extension = data + short(extension + 2)
	end

	return action.PASS
end

xdp.attach(filter_sni)

