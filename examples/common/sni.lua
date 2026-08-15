--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
--- Server Name Indication (SNI) parsing shared by the packet-filtering examples.
-- @module examples.common.sni

local HANDSHAKE      <const> = 0x16
local CLIENT_HELLO   <const> = 0x01
local SERVER_NAME    <const> = 0x0000
local SESSION        <const> = 43
local MAX_EXTENSIONS <const> = 17

local function u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

--- Returns the host name in the TLS ClientHello at `base`, or `nil`.
-- @function sni
-- @tparam userdata packet buffer answering `getbyte`/`getstring`
-- @tparam integer base offset of the TLS record within the packet
-- @treturn string|nil the host name
local function sni(packet, base)
	if packet:getbyte(base) ~= HANDSHAKE or packet:getbyte(base + 5) ~= CLIENT_HELLO then
		return
	end

	local cipher      = base + SESSION + 1 + packet:getbyte(base + SESSION)
	local compression = cipher + 2 + u16(packet, cipher)
	local extension   = compression + 3 + packet:getbyte(compression)

	for _ = 1, MAX_EXTENSIONS do
		local body = extension + 4
		if u16(packet, extension) == SERVER_NAME then
			return packet:getstring(body + 5, u16(packet, body + 3))
		end
		extension = body + u16(packet, extension + 2)
	end
end

return sni

