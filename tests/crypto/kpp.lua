--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto.kpp test (see run.sh).

local crypto  = require("crypto")
local hkdf    = require("crypto.hkdf")
local util    = require("util")
local closing = require("tests.crypto.closing")
local refusal = require("tests.crypto.refusal")
local lib     = require("tests.lib")

local char    = string.char
local rep     = string.rep
local hex2bin = util.hex2bin
local test    = lib.test
local raises  = lib.raises
local refuses = refusal.check

-- nil where the kernel has no CONFIG_CRYPTO_ECDH, which every ECDH provider selects
local kpp = crypto.kpp or error("the kernel serves no ecdh-nist-p256", 0)

-- the kernel's ecdh_p192_tv_template, ecdh_p256_tv_template and ecdh_p384_tv_template, without struct ecdh
local vectors <const> = {
	["ecdh-nist-p192"] = {
		scalar = hex2bin("b505b1711ebf8cda4e191e621f232331361ed3842fcc2172"),
		public = hex2bin(
			"1a04dba5e1dd4e79a3e6ef0e5c804985fa78b4ef49bd4c7c22902102f91b815d" ..
			"0c8aa898d62769885ebc94d8159e21ce"),
		peer = hex2bin(
			"c3ba674b71ecd0767a99756436139a945d8bdc609091fd3fb01f8a0a68c6886e" ..
			"8387dd6709f88d9607d6bd1ce68d9d67"),
		shared = hex2bin("f457cc4f1f4e31cce34060c80693c62e99808128afc55174"),
	},
	["ecdh-nist-p256"] = {
		scalar = hex2bin("24d121ebe5cf2d83f6621b6e43843aa38be086c32019da92505303e1c0eab882"),
		public = hex2bin(
			"1a7feb5200bd3c317db670c186a6c7c43bc55f6c6f583cf5b66382773324a15f" ..
			"6aca436ff77eff023708cc405e7afd6a6a026e4187683877faa944432def09df"),
		peer = hex2bin(
			"ccb4da74b1473fea6c709e382dc7aab729b2470319abdd34bda82c93e1a474d9" ..
			"6463f770202fa4e69f4a38ccc02c492fb132bbaf2261dacb6fdba9aafc7781f3"),
		shared = hex2bin("ea176f7e6e5726388bfb41ebbac86da5a872d1ffc9473daa58439f340f8cf3c9"),
	},
	["ecdh-nist-p384"] = {
		scalar = hex2bin(
			"099f3c7034d4a2c699884d73a375a67f7624ef7c6b3c0f160647b67414dce655" ..
			"e35b538041e649ee3faef896783ab194"),
		public = hex2bin(
			"667842d7d180ac2cde6f74f37551f55755c7645c20ef73e31634fe72b4c55ee6" ..
			"de3ac808acb4bdb4c88732aee95f41aa9482ed1fc0eeb9cafc4984625ccfc23f" ..
			"65032149e0e144ada024181535a0f38eeb9fcff3c2c947dae69b4c634573a81c"),
		peer = hex2bin(
			"e558dbef53eecde3d3fccfc1aea08a89a987475d12fd950d83cfa41732bc509d" ..
			"0d1ac43a0336def96fda41d0774a3571dcfbec7aacf3196472169e838430367f" ..
			"66eebe3c6e70c416dd5f0c68759dd1fff83fa40142209dff5eaad96db9e6386c"),
		shared = hex2bin(
			"11187331c279962d93d604243fd592cb9d0a926f422e47187521287e7156c5c4" ..
			"d603135569b9e9d09cf5d4a270f59746"),
	},
}

local U16MAX <const> = 65535 -- the most struct ecdh's key_size holds

local IV     <const> = rep("\1", 12)
local SECRET <const> = "the secret only the kernel opens"

-- the objects the cases allocate, before they run, so run.sh skips the test where the kernel lacks one
lib.alloc(kpp, "ecdh-nist-p256")
lib.alloc(kpp, "ecdh-nist-p384")
lib.alloc(crypto.aead, "gcm(aes)")
lib.alloc(hkdf.new, "sha256")

-- a name the kernel may not serve raises ENOENT, and one it serves raises expected
local function refusesname(expected, name, ...)
	local ok, err = pcall(kpp, name, ...)
	assert(not ok, name .. " was served")
	assert(err == expected or err == "ENOENT", name .. " raised " .. tostring(err))
end

local function agree(name, publiclen)
	local a <close> = kpp(name)
	local b <close> = kpp(name)
	local apublic, bpublic = a:publickey(), b:publickey()
	assert(#apublic == publiclen, name .. "'s public key is " .. #apublic .. " bytes")
	assert(apublic ~= bpublic, name .. " generated one key twice")
	local secret = a:sharedsecret(bpublic)
	assert(#secret == publiclen // 2, name .. "'s secret is " .. #secret .. " bytes")
	assert(secret == b:sharedsecret(apublic), name .. "'s two sides disagree")
end

local function answers(name)
	local vector = vectors[name]
	local ecdh <close> = kpp(name, vector.scalar)
	assert(ecdh:publickey() == vector.public, name .. "'s publickey does not match the vector")
	assert(ecdh:sharedsecret(vector.peer) == vector.shared, name .. "'s sharedsecret does not match the vector")
end

local function derive(secret)
	local h <close> = hkdf.new("sha256")
	return h:hkdf("", secret, "wrap", 32)
end

local function cipher(key)
	local gcm = crypto.aead("gcm(aes)")
	gcm:setkey(key)
	return gcm
end

test("crypto.kpp answers the kernel's ECDH vectors", function()
	answers("ecdh-nist-p256")
	answers("ecdh-nist-p384")
	local ok, err = pcall(answers, "ecdh-nist-p192") -- FIPS mode serves no ecdh-nist-p192
	assert(ok or err == "ENOENT", tostring(err))
end)

test("crypto.kpp agrees a secret between two generated keys", function()
	agree("ecdh-nist-p256", 64)
	agree("ecdh-nist-p384", 96)
	agree("ecdh-nist-p256-generic", 64)
	local ok, err = pcall(agree, "ecdh-nist-p192", 48) -- FIPS mode serves no ecdh-nist-p192
	assert(ok or err == "ENOENT", tostring(err))
end)

test("crypto.kpp opens a secret wrapped for a key generated in the kernel", function()
	local machine <close> = kpp("ecdh-nist-p256")

	local sender <close> = kpp("ecdh-nist-p256")
	local sealed = cipher(derive(sender:sharedsecret(machine:publickey()))):encrypt(IV, SECRET)
	local ephemeral = sender:publickey()

	local opened = cipher(derive(machine:sharedsecret(ephemeral))):decrypt(IV, sealed)
	assert(opened == SECRET, "the machine did not open the secret")
end)

test("crypto.kpp answers nil and EINVAL for a peer's key the curve refuses", function()
	local vector = vectors["ecdh-nist-p256"]
	local ecdh <close> = kpp("ecdh-nist-p256", vector.scalar)
	refuses(ecdh, vector.peer:sub(1, 63) .. char(vector.peer:byte(64) ~ 1)) -- off the curve
	refuses(ecdh, vector.peer:sub(1, 63))
	refuses(ecdh, vector.peer .. "\0")
	refuses(ecdh, rep("\0", 64))
	assert(ecdh:sharedsecret(vector.peer) == vector.shared, "a refused key changed the object")
end)

test("crypto.kpp refuses a private key of another length or out of the curve's range", function()
	local vector = vectors["ecdh-nist-p256"]
	raises("EINVAL", kpp, "ecdh-nist-p256", vector.scalar:sub(2))
	raises("EINVAL", kpp, "ecdh-nist-p384", vectors["ecdh-nist-p384"].scalar:sub(2))
	refusesname("EINVAL", "ecdh-nist-p192", vectors["ecdh-nist-p192"].scalar:sub(2))
	raises("EINVAL", kpp, "ecdh-nist-p256", "")
	raises("EINVAL", kpp, "ecdh-nist-p256", rep("\0", 32))
	raises("EINVAL", kpp, "ecdh-nist-p256", rep("\xff", 32))
	raises("EINVAL", kpp, "ecdh-nist-p256", vector.scalar .. rep("\0", U16MAX + 1))
end)

test("crypto.kpp refuses another key agreement and an unknown name", function()
	refusesname("EINVAL", "ffdhe2048(dh)")
	refusesname("EINVAL", "curve25519")
	refusesname("EINVAL", "curve25519", rep("\1", 26)) -- packed, the size of curve25519's own key
	raises("ENOENT", kpp, "ecdh-nist-p1")
end)

test("crypto.kpp names its algorithm", function()
	local ecdh <close> = kpp("ecdh-nist-p256")
	assert(ecdh:algname() == "ecdh-nist-p256", "algname answered " .. ecdh:algname())
end)

test("crypto.kpp:close releases the transform, and __close is close", function()
	closing.check(kpp("ecdh-nist-p256"), "publickey")
end)

