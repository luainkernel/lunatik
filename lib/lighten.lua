--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Encrypted Lua script support (AES-256-GCM).
-- This module provides functions to run encrypted Lua scripts
-- using the `darken` C module.
--
-- The key is the module `light`, `/lib/modules/lua/light.lua`, which returns the hex-encoded
-- 32-byte key; without it, `require("lighten")` raises "module 'light' not found".
-- `tools/shade.sh darken [-s <secret>] <script>.lua` encrypts a script into `<script>.dark.lua`,
-- which calls `lighten.run`, and prints the secret, 64 hex characters;
-- `tools/shade.sh lighten <secret>` writes `light.lua` from it. With `-t` both derive the key from
-- the current 30 second step, so `light.lua` and the dark script are generated in the same step:
--
--     SECRET=$(tools/shade.sh darken hello.lua)
--     tools/shade.sh lighten "$SECRET"
--     sudo cp light.lua hello.dark.lua /lib/modules/lua/
--     sudo lunatik run hello.dark
--
-- @module lighten

local light = require("light")
local darken = require("darken")
local hex2bin = require("util").hex2bin

local lighten = {}

--- Decrypts and executes an encrypted Lua script.
-- @tparam string ct Hex-encoded ciphertext followed by its 16-byte tag.
-- @tparam string iv Hex-encoded 12-byte IV.
-- @return The return values of the decrypted script.
-- @raise `"invalid hexadecimal string"` when `ct`, `iv` or the key is not hexadecimal of an even length,
-- or the error `darken.run` raises.
-- @see darken.run
function lighten.run(ct, iv)
	return darken.run(hex2bin(ct), hex2bin(iv), hex2bin(light))
end

return lighten

