--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Kernel TLS (kTLS): the `tls_crypto_info` blob a socket carrying the `tls`
-- ULP is keyed with, the two version numbers the kernel accepts, and the record
-- types `socket:sendrecord` and `socket:receiverecord` carry. Negotiating the
-- keys is userspace's; this only assembles the payload the second `setsockopt`
-- takes.
-- @module tls
-- @see socket
-- @usage
-- local tls  = require("tls")
-- local sk   = require("linux.socket")
-- local ltls = require("linux.tls")
--
-- sock:setsockopt(sk.sol.TCP, sk.tcp.ULP, "tls")
-- sock:setsockopt(sk.sol.TLS, ltls.TX,
--     tls.pack(tls.version.TLS_1_3, ltls.cipher.AES_GCM_128, iv, key, salt, rec_seq))

local ltls   = require("linux.tls")
local struct = require("struct")

local char   = string.char
local format = string.format

-- the two bytes a close_notify carries, TLS_ALERT_LEVEL_WARNING and
-- TLS_ALERT_DESC_CLOSE_NOTIFY
local LEVEL_WARNING <const> = 1
local CLOSE_NOTIFY  <const> = 0

local tls = {}

-- the header do_tls_setsockopt_conf reads before it knows how long the rest is
local crypto_info = struct(ltls.layout.crypto_info)

-- cipher id -> the four key material sizes linux.tls.size keys under its name
local sizes = {}
for name, cipher in pairs(ltls.cipher) do
	sizes[cipher] = {
		iv      = ltls.size[name .. "_IV_SIZE"],
		key     = ltls.size[name .. "_KEY_SIZE"],
		salt    = ltls.size[name .. "_SALT_SIZE"],
		rec_seq = ltls.size[name .. "_REC_SEQ_SIZE"],
	}
end

-- TLS_VERSION_NUMBER, which autogen cannot emit: a function-like macro is not
-- an integer constant expression, so only the halves reach linux.tls
local function versionnumber(id)
	return (ltls[id .. "_VERSION_MAJOR"] << 8) | ltls[id .. "_VERSION_MINOR"]
end

local function checkfield(what, part, expected)
	local got = #part
	if got ~= expected then
		error(format("%s is %d bytes, cipher expects %d", what, got, expected))
	end
end

---
-- The versions `validate_crypto_info` accepts, composed from the halves
-- `linux.tls` carries.
-- @table version
-- @field TLS_1_2 `0x0303`
-- @field TLS_1_3 `0x0304`
tls.version = { TLS_1_2 = versionnumber("1_2"), TLS_1_3 = versionnumber("1_3") }

---
-- The TLS content types, as `socket:sendrecord` takes one and
-- `socket:receiverecord` reports one. Written here rather than generated:
-- `net/tls_prot.h`, which names them, arrived in 6.6, above the oldest kernel
-- this module supports.
-- @table record
-- @field CHANGE_CIPHER_SPEC `20`
-- @field ALERT `21`
-- @field HANDSHAKE `22`
-- @field DATA `23`
-- @field HEARTBEAT `24`
-- @field TLS12_CID `25`
-- @field ACK `26`
tls.record = {
	CHANGE_CIPHER_SPEC = 20,
	ALERT              = 21,
	HANDSHAKE          = 22,
	DATA               = 23,
	HEARTBEAT          = 24,
	TLS12_CID          = 25,
	ACK                = 26,
}

---
-- Packs the `tls_crypto_info` blob for `setsockopt(SOL_TLS, TLS_TX|TLS_RX)`:
-- the `{version, cipher_type}` header, then the cipher's key material flat and
-- in this order. Each part is exactly the size `linux.tls.size` gives that
-- cipher. The version is not inspected here, the kernel refuses the ones it
-- does not implement.
-- @function pack
-- @tparam integer version a `tls.version` entry
-- @tparam integer cipher a `linux.tls.cipher` entry
-- @tparam string iv the explicit nonce
-- @tparam string key the record key
-- @tparam[opt] string salt the implicit nonce, `nil` for a cipher whose salt size is zero
-- @tparam string rec_seq the initial record sequence number
-- @treturn string the blob, `4 + iv + key + salt + rec_seq` bytes long
-- @raise `unknown cipher 59`, or `key is 8 bytes, cipher expects 16`
function tls.pack(version, cipher, iv, key, salt, rec_seq)
	local size = sizes[cipher]
	if size == nil then
		error("unknown cipher " .. tostring(cipher))
	end
	iv, key, salt, rec_seq = iv or "", key or "", salt or "", rec_seq or ""
	checkfield("iv", iv, size.iv)
	checkfield("key", key, size.key)
	checkfield("salt", salt, size.salt)
	checkfield("rec_seq", rec_seq, size.rec_seq)
	return crypto_info:pack(version, cipher) .. iv .. key .. salt .. rec_seq
end

---
-- Sends a `close_notify`, the alert that ends a TLS session cleanly. The peer
-- reads a record of type `tls.record.ALERT` carrying the level and the
-- description, the same two bytes the kernel's own `tls_alert_send` emits.
-- @function close_notify
-- @tparam socket sock a socket whose transmit direction is keyed
-- @treturn integer the number of bytes sent, 2
-- @raise Error if the send fails
-- @see socket.sendrecord
function tls.close_notify(sock)
	return sock:sendrecord(tls.record.ALERT, char(LEVEL_WARNING, CLOSE_NOTIFY))
end

return tls

