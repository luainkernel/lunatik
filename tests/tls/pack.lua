--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tls.pack test (see pack.sh).

local tls    = require("tls")
local struct = require("struct")
local ltls   = require("linux.tls")

local rep = string.rep

local TLS13  <const> = tls.version.TLS_1_3
local AES    <const> = ltls.cipher.AES_GCM_128
local CHACHA <const> = ltls.cipher.CHACHA20_POLY1305

-- a version number the kernel does not implement: the packer must not judge it
local BADVERSION <const> = 0x0305

-- the ids probed for a refusal: TLS_CIPHER_MIN..MAX with a margin on each side
local FIRST <const> = 0
local LAST  <const> = 64

-- the sizes gcc measures for the tls12_crypto_info_* structs, which pad
-- nowhere: two __u16 and then four unsigned char arrays
local measured = {
	AES_GCM_128 = 40, AES_GCM_256 = 56, AES_CCM_128 = 40, CHACHA20_POLY1305 = 56,
	SM4_GCM = 40, SM4_CCM = 40, ARIA_GCM_128 = 40, ARIA_GCM_256 = 56,
}

-- what the module is documented to carry, the two numbers TLS_VERSION_NUMBER
-- composes, and the content types net/tls_prot.h names
local surface = { pack = "function", version = "table", record = "table", close_notify = "function" }
local versions = { TLS_1_2 = 0x0303, TLS_1_3 = 0x0304 }
local records = {
	CHANGE_CIPHER_SPEC = 20, ALERT = 21, HANDSHAKE = 22, DATA = 23,
	HEARTBEAT = 24, TLS12_CID = 25, ACK = 26,
}

local crypto_info = struct(ltls.layout.crypto_info)

local names = {}
for name, cipher in pairs(ltls.cipher) do names[cipher] = name end

-- the four parts at exactly the sizes linux.tls.size gives that cipher, each
-- filled with a byte of its own so a packer that reorders them is caught
local function material(name)
	return rep("\1", ltls.size[name .. "_IV_SIZE"]), rep("\2", ltls.size[name .. "_KEY_SIZE"]),
		rep("\3", ltls.size[name .. "_SALT_SIZE"]), rep("\4", ltls.size[name .. "_REC_SEQ_SIZE"])
end

local function refuses(message, ...)
	local ok, err = pcall(tls.pack, ...)
	assert(not ok, "pack accepted what should raise '" .. message .. "'")
	assert(err:find(message, 1, true), "expected '" .. message .. "', got " .. tostring(err))
end

-- the module is the packer, the two version numbers, the record types and the
-- close_notify helper, and carries nothing else
for name, kind in pairs(surface) do
	assert(type(tls[name]) == kind, name .. " is a " .. type(tls[name]))
end
for name in pairs(tls) do
	assert(surface[name] ~= nil, "tls also carries " .. name)
end
for name, value in pairs(versions) do
	assert(tls.version[name] == value, name .. ": " .. tostring(tls.version[name]))
end
for name in pairs(tls.version) do
	assert(versions[name] ~= nil, "tls.version also carries " .. name)
end
for name, value in pairs(records) do
	assert(tls.record[name] == value, name .. ": " .. tostring(tls.record[name]))
end
for name in pairs(tls.record) do
	assert(records[name] ~= nil, "tls.record also carries " .. name)
end

print("tls pack: the module carries the packer, the versions and the record types")

-- every cipher's blob is the length do_tls_setsockopt_conf demands of it
for cipher, name in pairs(names) do
	local blob = tls.pack(TLS13, cipher, material(name))
	assert(#blob == measured[name], name .. " packs " .. #blob .. " bytes, expected " .. tostring(measured[name]))
end

-- validate_crypto_info is what refuses a version, so the blob is built either way
assert(#tls.pack(BADVERSION, AES, material("AES_GCM_128")) == measured.AES_GCM_128,
	"a version the kernel refuses changed the blob size")

print("tls pack: every cipher sized")

-- the header and the key material sit where tls_cipher_desc reads them
local iv, key, salt, rec_seq = material("AES_GCM_128")
local blob = tls.pack(TLS13, AES, iv, key, salt, rec_seq)
local version, cipher_type = crypto_info:unpack(blob)
assert(version == TLS13, "version: " .. version)
assert(cipher_type == AES, "cipher_type: " .. cipher_type)
assert(#blob == measured.AES_GCM_128, "the blob is " .. #blob .. " bytes")
assert(blob:sub(5, 12) == iv, "iv is not at bytes 5..12")
assert(blob:sub(13, 28) == key, "key is not at bytes 13..28")
assert(blob:sub(29, 32) == salt, "salt is not at bytes 29..32")
assert(blob:sub(33, 40) == rec_seq, "rec_seq is not at bytes 33..40")

print("tls pack: fields in order")

-- a field of the wrong length is refused, and the message names which one
refuses("key is 8 bytes, cipher expects 16", TLS13, AES, iv, rep("\2", 8), salt, rec_seq)
refuses("iv is 9 bytes, cipher expects 8", TLS13, AES, rep("\1", 9), key, salt, rec_seq)
refuses("rec_seq is 4 bytes, cipher expects 8", TLS13, AES, iv, key, salt, rep("\4", 4))

-- the zero-salt cipher is sized like the others, not special-cased away
local civ, ckey, csalt, cseq = material("CHACHA20_POLY1305")
assert(#csalt == 0, "CHACHA20_POLY1305 salt size is " .. #csalt)
refuses("salt is 1 bytes, cipher expects 0", TLS13, CHACHA, civ, ckey, "\3", cseq)
local nosalt = tls.pack(TLS13, CHACHA, civ, ckey, nil, cseq)
assert(#nosalt == measured.CHACHA20_POLY1305, "the salt-less blob is " .. #nosalt .. " bytes")

print("tls pack: wrong length refused")

-- the ciphers pack accepts are exactly the ones linux.tls.cipher carries
for cipher = FIRST, LAST do
	local name = names[cipher]
	if name == nil then
		refuses("unknown cipher " .. cipher, TLS13, cipher)
	else
		tls.pack(TLS13, cipher, material(name))
	end
end
refuses("unknown cipher nil", TLS13, nil)

print("tls pack: unknown cipher refused")

