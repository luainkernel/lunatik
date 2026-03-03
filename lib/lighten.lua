--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Encrypted Lua script support (AES-256-CTR).
-- This module provides functions to run encrypted Lua scripts
-- using the `darken` C module.
-- @module lighten

local light = require("light")
local darken = require("darken")
local hex2bin = require("util").hex2bin

local lighten = {}

--- Decrypts and executes an encrypted Lua script.
-- @tparam string ct Hex-encoded ciphertext.
-- @tparam string iv Hex-encoded 16-byte IV.
-- @return The return values of the decrypted script.
function lighten.run(ct, iv)
	return darken.run(hex2bin(ct), hex2bin(iv), hex2bin(light))
end

return lighten

