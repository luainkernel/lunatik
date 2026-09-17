--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
--- Server Name Indication (SNI) parsing shared by the packet-filtering examples.
--
-- One source for both sides: a kernel Lua script calls it over the `data` object it is handed,
-- and a compiled program file over the packet proxy, which publishes the same reads.
-- @module examples.common.sni

local HANDSHAKE      <const> = 0x16
local CLIENT_HELLO   <const> = 0x01
local SERVER_NAME    <const> = 0x0000
local SESSION        <const> = 43
local MAX_EXTENSIONS <const> = 17
local MAX_HOST       <const> = 64

local sni = {}

--- The big-endian sixteen-bit number at `at`.
-- @function examples.common.sni.u16
-- @tparam userdata packet a buffer answering `getbyte`
-- @tparam integer at the offset to read from
-- @treturn integer
function sni.u16(packet, at)
	return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
end

--- Returns the host name in the TLS ClientHello at `base`, or `nil`.
--
-- A name of no bytes, or of more than 64, answers nothing on both sides: a compiled read is
-- bounded by that constant while it compiles, and `luadata_checkbounds` raises on an empty read
-- in the kernel object, so the two agree only where this refuses both first.
-- @function examples.common.sni.host
-- @tparam userdata packet a buffer answering `getbyte` and `getstring`
-- @tparam integer base offset of the TLS record within the packet
-- @treturn string|nil the host name
function sni.host(packet, base)
	if packet:getbyte(base) ~= HANDSHAKE or packet:getbyte(base + 5) ~= CLIENT_HELLO then
		return
	end

	local cipher      = base + SESSION + 1 + packet:getbyte(base + SESSION)
	local compression = cipher + 2 + sni.u16(packet, cipher)
	local extension   = compression + 3 + packet:getbyte(compression)

	for _ = 1, MAX_EXTENSIONS do
		local body = extension + 4
		if sni.u16(packet, extension) == SERVER_NAME then
			local length = sni.u16(packet, body + 3)
			if length < 1 or length > MAX_HOST then
				return
			end
			-- a local, since `return packet:getstring(...)` is a tail call, which the compiler refuses
			local host = packet:getstring(body + 5, length)
			return host
		end
		extension = body + sni.u16(packet, extension + 2)
	end
end

return sni

