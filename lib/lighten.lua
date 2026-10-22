--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Encrypted Lua script support (AES-256-GCM).
-- This module provides functions to load and run encrypted Lua scripts
-- using the `darken` C module.
--
-- The key is the module `light`, `/lib/modules/lua/light.lua`, which returns the hex-encoded
-- 32-byte key. The kernel opens it with the credentials of the task that first requires `lighten`
-- in the runtime, and the recipe below installs it readable by root alone, so that require must come
-- from a root task, as it does in a script `lunatik run` or `lunatik spawn` runs, not from a callback
-- an unprivileged task drives, such as a `device` read. Without the file, or from a task that cannot
-- read it, `require("lighten")` raises "module 'light' not found".
-- `tools/shade.sh darken [-s] <script>.lua` encrypts a script into `<script>.dark.lua`,
-- which calls what `lighten.load` returns with its own arguments, and prints the secret, 64 hex
-- characters, a new one or, with `-s`, the one it reads on stdin;
-- `tools/shade.sh lighten` writes `light.lua` from the secret it reads on stdin. With `-t` both derive
-- the key from the current 30 second step, so `light.lua` and the dark script are generated in the
-- same step:
--
--     SECRET=$(tools/shade.sh darken hello.lua)
--     tools/shade.sh lighten <<< "$SECRET"
--     sudo install -m 0600 light.lua /lib/modules/lua/
--     sudo cp hello.dark.lua /lib/modules/lua/
--     sudo lunatik run hello.dark
--
-- A runtime that sets `package.loaded.light` to a hex key of its own, or `package.preload.light` to
-- a function that returns one, before it first requires `lighten`, lightens with that key instead,
-- which no other runtime reaches. Since `lunatik run hello.dark` runs nothing before the dark
-- script, a runtime run that way reads `light.lua`, and one with its own key runs a script that sets
-- it and then requires the dark modules, each installed where `require` finds its name, as
-- `hello/dark.lua` for `require("hello.dark")`. A caller that holds the ciphertext, the IV and the
-- key calls `darken.load` or `darken.run` itself, which take all three in binary: `util.hex2bin`
-- decodes the hex `tools/shade.sh` writes.
--
-- @module lighten

local light = require("light")
local darken = require("darken")
local hex2bin = require("util").hex2bin

local lighten = {}

--- Decrypts and loads an encrypted Lua script without running it.
-- @tparam string ct Hex-encoded ciphertext followed by its 16-byte tag.
-- @tparam string iv Hex-encoded 12-byte IV.
-- @treturn function the loaded script.
-- @raise `"invalid hexadecimal string"` when `ct`, `iv` or the key is not hexadecimal of an even length,
-- or the error `darken.load` raises.
-- @see darken.load
function lighten.load(ct, iv)
	return darken.load(hex2bin(ct), hex2bin(iv), hex2bin(light))
end

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

