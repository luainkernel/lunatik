--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto.sig test (see run.sh).

local crypto  = require("crypto")
local util    = require("util")
local closing = require("tests.crypto.closing")
local lib     = require("tests.lib")

local sig     = crypto.sig
local test    = lib.test
local hex2bin = util.hex2bin
local char    = string.char
local rep     = string.rep

-- the entry of the kernel's ecdsa_nist_p256_tv_template over a SHA-256 digest
local POINT <const> = hex2bin(
	"04f1eac453f3b90e9f7eade3ead70e0fd6989aca924d0a80db2d45c7ec4b97002fe9426c29dc550e0b53129b2bad2ce9" ..
	"80e6c543c21d5ebb652150b637b0038eb8")
local DIGEST <const> = hex2bin("8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4")
local SIGNATURE <const> = hex2bin(
	"304502200831fa740d1d215d09dc2963a81aadfcac44c3e824112da491dc0267dc0cd082022100bdffceee42c397fff9" ..
	"a981ac4a50d0910a6e1bc4afe183c34f2a653523e31dfa")

-- a 2048-bit RSAPublicKey and the PKCS#1 v1.5 signature of SHA-256(MESSAGE) openssl made with its key
local RSAKEY <const> = hex2bin(
	"3082010a0282010100ae718a446d09c18b93149ec9307eca269b4f9379e1ab2d851441bfa28127246b3013cc946c17f0" ..
	"d718b5972c71970c38c4028ca505c829912d56ccd4492a707ef70a4080c73eb42792d4a2d5364db8d799173b12f1ae64" ..
	"cb3435397bbe30ad5103eebde9446610abb7e51bb79a8d726292f94bc3fee0334cea7ec6fc9da40fcaf394eb9c1d6cd6" ..
	"93fc690e8d7eb54fc7cac633abc0581e28554ae46950fb330a89d3d58a7cbbd0a2cca9b33fa684184ddf5093883f7501" ..
	"fc553bb18ed4aeff2a41fcbf567fe8b76ee3dd85d3e13c35d620a27b5393b8e5f3bc57df44c53de125f4bf636164ed43" ..
	"c792806a15120f92a1764b65ff16a07a5e4d89e36ec732e52b0203010001")
local RSASIGNATURE <const> = hex2bin(
	"183dab27ccfd7ddde515a258439a0ea7f785ab8f08cf74848fb1c1ec43270971658242634b3ff37826f99b64991ca064" ..
	"3855a0866d790d9734b2a0065e8f9ba3bd41bc1b551a3297c51f58b24814e7d5fd9f383301d6e5df76a1e19277b80356" ..
	"7e070ff36206087ccaf8c5e5c4bde586e7e4eabca17e04c4a54496c008fc6372360804a0ba2b9f02784f57961184e305" ..
	"3bf3d2c80ae2236c63deeb0fa273eb1f47d147634deaee92d9a907f2329367dd10bd6b97ceccc951e81f82e5cc2a1c76" ..
	"3bb96095125f227e6237672e3cb8206c292203ebc63a0d631a289499ce948b38a52658e60ed5242ab782a4cd9faa0be9" ..
	"d830da68ef7f234d93ee6c6e72afd036")
local MESSAGE <const> = "The quick brown fox jumps over the lazy dog"
local RSADIGEST <const> = lib.alloc(crypto.shash, "sha256"):digest(MESSAGE)

local MAXLEN <const> = 65535 -- the length verify bounds each string to
local RSAMAXSIZE <const> = 256 -- the key's size, as the kernel gives it for RSA
local P256MAXSIZE <const> = 32 -- the key's size, as ecdsa_max_size gives it
local X962MAXSIZE <const> = 72 -- the DER bound, as ecdsa_x962_max_size gives it

-- r of 34 bytes, past the 33 a P-256 integer takes with its sign byte
local LONGR <const> = "\x30\x46\x02\x22" .. rep("\x01", 34) .. "\x02\x20" .. rep("\x01", 32)
-- n of 256 bits, a size RSA does not take
local SHORTRSAKEY <const> = "\x30\x25\x02\x20" .. rep("\x7f", 32) .. "\x02\x01\x03"

local function new(name, older)
	local ok, verifier = pcall(sig, name)
	if ok then
		return verifier, name
	end
	assert(verifier == "ENOENT", name .. " raised " .. tostring(verifier))
	return lib.alloc(sig, older), older
end

local function ecdsa()
	return new("x962(ecdsa-nist-p256)", "ecdsa-nist-p256")
end

local function rsa()
	return new("pkcs1(rsa,sha256)", "pkcs1pad(rsa,sha256)")
end

-- the verifiers the cases allocate, before they run, so run.sh skips the test where the kernel lacks one
ecdsa()
rsa()

local function flip(s, i)
	return s:sub(1, i - 1) .. char(s:byte(i) ~ 1) .. s:sub(i + 1)
end

local function raises(expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, "no raise where " .. expected .. " was expected")
	err = tostring(err)
	assert(err:find(expected, 1, true), "raised " .. err .. " where " .. expected .. " was expected")
end

local function rejects(verifier, errname, signature, digest)
	local ok, err = verifier:verify(signature, digest)
	assert(ok == false, "verify answered " .. tostring(ok) .. " where false and " .. errname .. " were expected")
	assert(err == errname, "verify answered " .. tostring(err) .. " where " .. errname .. " was expected")
end

local function keyed(verifier, key)
	verifier:setpubkey(key)
	return verifier
end

test("crypto.sig verifies the kernel's ECDSA P-256 vector", function()
	local verifier <close> = keyed(ecdsa(), POINT)
	assert(verifier:verify(SIGNATURE, DIGEST) == true, "the vector did not verify")
end)

test("crypto.sig answers false for an ECDSA signature that does not verify or parse", function()
	local verifier <close> = keyed(ecdsa(), POINT)
	rejects(verifier, "EKEYREJECTED", flip(SIGNATURE, #SIGNATURE), DIGEST)
	rejects(verifier, "EKEYREJECTED", SIGNATURE, flip(DIGEST, 1))
	rejects(verifier, "EBADMSG", rep("\0", #SIGNATURE), DIGEST)
	rejects(verifier, "EBADMSG", "", DIGEST)
	rejects(verifier, "EINVAL", LONGR, DIGEST)
end)

test("crypto.sig names the algorithm it allocated, and maxsize is the kernel's", function()
	local verifier <close>, name = ecdsa()
	verifier:setpubkey(POINT)
	assert(verifier:algname() == name, "algname answered " .. verifier:algname())
	local expected = name == "ecdsa-nist-p256" and P256MAXSIZE or X962MAXSIZE
	assert(verifier:maxsize() == expected, "maxsize answered " .. verifier:maxsize())
end)

test("crypto.sig refuses a key ECDSA refuses, and a failed key leaves it unkeyed", function()
	local verifier <close> = keyed(ecdsa(), POINT)
	raises("EINVAL", verifier.setpubkey, verifier, "\x02" .. POINT:sub(2))
	raises("ENOKEY", verifier.verify, verifier, SIGNATURE, DIGEST)
	raises("ENOKEY", verifier.maxsize, verifier)
	raises("EINVAL", verifier.setpubkey, verifier, POINT:sub(1, -2))
	raises("EINVAL", verifier.setpubkey, verifier, flip(POINT, #POINT))
	raises("ENOKEY", verifier.verify, verifier, SIGNATURE, DIGEST)
	verifier:setpubkey(POINT)
	assert(verifier:verify(SIGNATURE, DIGEST) == true, "the vector did not verify under the key set again")
end)

test("crypto.sig raises ENOKEY before a key is set", function()
	for _, new in ipairs{ecdsa, rsa} do
		local verifier <close> = new()
		raises("ENOKEY", verifier.verify, verifier, SIGNATURE, DIGEST)
		raises("ENOKEY", verifier.maxsize, verifier)
	end
end)

test("crypto.sig bounds the signature and the digest", function()
	local verifier <close> = keyed(ecdsa(), POINT)
	raises("out of bounds", verifier.verify, verifier, rep("\0", MAXLEN + 1), DIGEST)
	raises("out of bounds", verifier.verify, verifier, SIGNATURE, "")
	raises("out of bounds", verifier.verify, verifier, SIGNATURE, rep("\0", MAXLEN + 1))
	rejects(verifier, "EBADMSG", rep("\0", MAXLEN), DIGEST)
	local long = DIGEST .. rep("\0", MAXLEN - #DIGEST) -- ECDSA reads the curve's size from its left
	assert(verifier:verify(SIGNATURE, long) == true, "the vector did not verify with its digest padded")
end)

test("crypto.sig verifies an RSA PKCS#1 v1.5 signature", function()
	local verifier <close> = keyed(rsa(), RSAKEY)
	assert(verifier:verify(RSASIGNATURE, RSADIGEST) == true, "the RSA signature did not verify")
	assert(verifier:maxsize() == RSAMAXSIZE, "maxsize answered " .. verifier:maxsize())
	rejects(verifier, "EKEYREJECTED", RSASIGNATURE, flip(RSADIGEST, 1))
	rejects(verifier, "EINVAL", RSASIGNATURE:sub(2), RSADIGEST)
end)

test("crypto.sig refuses an RSA key that does not parse or that RSA refuses", function()
	local verifier <close> = keyed(rsa(), RSAKEY)
	raises("EBADMSG", verifier.setpubkey, verifier, RSAKEY:sub(1, 100))
	raises("ENOKEY", verifier.maxsize, verifier)
	raises("EINVAL", verifier.setpubkey, verifier, SHORTRSAKEY)
	raises("ENOKEY", verifier.verify, verifier, RSASIGNATURE, RSADIGEST)
end)

test("crypto.sig serves the rsa akcipher only where the kernel wraps it", function()
	local padding <close>, name = rsa()
	if name ~= "pkcs1pad(rsa,sha256)" then
		raises("ENOENT", sig, "rsa")
		return
	end
	local verifier <close> = sig("rsa")
	raises("ENOKEY", verifier.maxsize, verifier)
	raises("ENOKEY", verifier.verify, verifier, RSASIGNATURE, RSADIGEST)
	verifier:setpubkey(RSAKEY)
	assert(verifier:maxsize() == RSAMAXSIZE, "maxsize answered " .. verifier:maxsize())
	raises("ENOSYS", verifier.verify, verifier, RSASIGNATURE, RSADIGEST)
	raises("EBADMSG", verifier.setpubkey, verifier, RSAKEY:sub(1, 100))
	raises("ENOKEY", verifier.maxsize, verifier)
end)

test("crypto.sig refuses an unknown name", function()
	raises("ENOENT", sig, "nosuchsig")
end)

test("crypto.sig:close releases the transform, and __close is close", function()
	closing.check(ecdsa(), "algname")
end)

