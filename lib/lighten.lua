--- Encrypted Lua script support (AES-256-CTR).
-- @module lighten

local light = require("light")
local darken = require("darken")
local hex2bin = require("util").hex2bin

local lighten = {}

--- Decrypts and executes an encrypted Lua script.
-- @tparam string ct Hex-encoded ciphertext.
-- @tparam string iv Hex-encoded 16-byte IV.
-- @return Decrypted script's return values.
function lighten.run(ct, iv)
	return darken.run(hex2bin(ct), hex2bin(iv), hex2bin(light))
end

return lighten

