--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq runtime for the crypto quic test (see run.sh).

local crypto  = require("crypto")
local hex2bin = require("util").hex2bin

local hasher   = crypto.shash("hmac(sha256)")
local importer = crypto.shash("hmac(sha256)")

local SALT    <const> = hex2bin("38762cf7f55934b34d179ae6a4c80cadccbb7f0a") -- RFC 9001 5.2, QUIC v1's
local HEAD    <const> = hex2bin("8394c8f0") -- RFC 9001 A.1's destination connection ID, its first half
local TAIL    <const> = hex2bin("3e515708") -- and its second
local INITIAL <const> = hex2bin("7db5df06e7a69e432496adedb00851923595221596ae2ae9fb8115c1e9ed0a44") -- A.1's

local function extract()
	hasher:setkey(SALT)
	importer:setkey(SALT) -- hmac's final reads the outer pad of the transform that imported the state
	local digest = hasher:digest(HEAD .. TAIL)
	assert(digest == INITIAL, "digest mismatch")

	hasher:init()
	hasher:update(HEAD)
	hasher:update(TAIL)
	assert(hasher:final() == digest, "final mismatch")

	hasher:init()
	hasher:update(HEAD)
	assert(hasher:finup(TAIL) == digest, "finup mismatch")

	hasher:init()
	hasher:update(HEAD)
	local state = hasher:export()
	importer:init()
	importer:import(state)
	importer:update(TAIL)
	assert(importer:final() == digest, "import mismatch")
end

return extract

