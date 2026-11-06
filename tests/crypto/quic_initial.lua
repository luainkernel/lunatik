--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq runtime for the crypto quic test (see run.sh).

local crypto  = require("crypto")
local hkdf    = require("crypto.hkdf").new("sha256")
local hex2bin = require("util").hex2bin

local hp      = crypto.skcipher("ecb(aes)")
local payload = crypto.skcipher("ctr(aes)")

local pack, unpack, rep = string.pack, string.unpack, string.rep

local SALT    <const> = hex2bin("38762cf7f55934b34d179ae6a4c80cadccbb7f0a") -- RFC 9001 5.2, QUIC v1's
local SAMPLE  <const> = 16
local TAG     <const> = 16
local COUNTER <const> = "\0\0\0\2" -- gcm(aes) ciphers with ctr(aes) from the second counter

-- RFC 9001 A.1 and A.2
local SECRET <const> = hex2bin("c00cf151ca5be075ed0ebfb5c80323c42d6b7db67881289af4008f1f6c357aea")
local KEY    <const> = hex2bin("1f369613dd76d5467730efcbe3b1a22d")
local IV     <const> = hex2bin("fa044b2f42a3fd3b46fb255c")
local HP     <const> = hex2bin("9f50449e04a0e810283a1e9933adedd2")
local MASK   <const> = hex2bin("437b9aec36")
local HEADER <const> = hex2bin("c300000001088394c8f03e5157080000449e00000002")
local FRAME  <const> = hex2bin(
	"060040f1010000ed0303ebf8fa56f12939b9584a3896472ec40bb863cfd3e868" ..
	"04fe3a47f06a2b69484c00000413011302010000c000000010000e00000b6578" ..
	"616d706c652e636f6dff01000100000a00080006001d00170018001000070005" ..
	"04616c706e000500050100000000003300260024001d00209370b2c9caa47fba" ..
	"baf4559fedba753de171fa71f50f1ce15d43e994ec74d748002b000302030400" ..
	"0d0010000e0403050306030203080408050806002d00020101001c0002400100" ..
	"3900320408ffffffffffffffff05048000ffff07048000ffff08011001048000" ..
	"75300901100f088394c8f03e51570806048000ffff"
)

local function expect(name, got, want)
	assert(got == want, name .. " mismatch")
end

local function expand(secret, label, length) -- HKDF-Expand-Label with an empty context, RFC 8446 7.1
	return hkdf:expand(secret, pack(">Hs1s1", length, "tls13 " .. label, ""), length)
end

local function varint(packet, offset) -- RFC 9000 16: the two high bits of the first byte give its length
	local first = packet:getuint8(offset)
	local length = 1 << (first >> 6)
	local value = first & 0x3f
	for i = 1, length - 1 do
		value = value << 8 | packet:getuint8(offset + i)
	end
	return value, offset + length
end

-- the packet number follows the connection IDs, the token and the length, RFC 9000 17.2.2
local function locate(packet)
	local dcid = packet:getstring(6, packet:getuint8(5))
	local offset = 6 + #dcid
	offset = offset + 1 + packet:getuint8(offset) -- the source connection ID
	local token, length
	token, offset = varint(packet, offset)
	length, offset = varint(packet, offset + token)
	return dcid, offset, length
end

local function unprotect(packet, offset, mask) -- RFC 9001 5.4.1, in place
	local first = packet:getuint8(0) ~ (mask:byte(1) & 0x0f)
	local pnlen = (first & 0x03) + 1
	local pn = 0
	packet:setuint8(0, first)
	for i = 0, pnlen - 1 do
		local byte = packet:getuint8(offset + i) ~ mask:byte(2 + i)
		packet:setuint8(offset + i, byte)
		pn = pn << 8 | byte
	end
	return pn, pnlen
end

local function open(packet)
	local dcid, offset, length = locate(packet)
	local secret = expand(hkdf:extract(SALT, dcid), "client in", 32)
	expect("client_initial_secret", secret, SECRET)

	local hpkey = expand(secret, "quic hp", 16)
	expect("hp", hpkey, HP)
	hp:setkey(hpkey)
	local mask = hp:encrypt("", packet:getstring(offset + 4, SAMPLE))
	expect("mask", mask:sub(1, #MASK), MASK)
	local pn, pnlen = unprotect(packet, offset, mask)
	expect("header", packet:getstring(0, offset + pnlen), HEADER)

	local key, iv = expand(secret, "quic key", 16), expand(secret, "quic iv", 12)
	expect("key", key, KEY)
	expect("iv", iv, IV)
	payload:setkey(key)
	local nonce = iv:sub(1, 8) .. pack(">I4", unpack(">I4", iv, 9) ~ pn) -- RFC 9001 5.3
	local frames = length - pnlen - TAG
	local plaintext = payload:decrypt(nonce .. COUNTER, packet:getstring(offset + pnlen, frames))
	expect("payload", plaintext, FRAME .. rep("\0", frames - #FRAME))
end

return open

