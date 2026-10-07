--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the darken decrypt test (see run.sh).

local darken = require("darken")
local aead   = require("crypto").aead
local test   = require("tests.lib").test

local KEY      <const> = string.rep("k", 32)
local IV       <const> = string.rep("i", 12)
local TAGLEN   <const> = 16
local MISMATCH <const> = "EBADMSG"
local LARGE    <const> = 64 << 20

local gcm = aead("gcm(aes)")
gcm:setkey(KEY)

local function seal(script)
	return gcm:encrypt(IV, script)
end

local function flip(s, i)
	return s:sub(1, i - 1) .. string.char(s:byte(i) ~ 1) .. s:sub(i + 1)
end

local function raises(expected, ...)
	local ok, err = pcall(darken.run, ...)
	assert(not ok, "darken.run did not raise " .. expected)
	assert(err:find(expected, 1, true), "expected " .. expected .. ", got " .. tostring(err))
end

local sealed = seal("return 1, 'two'")

test("darken.run runs a script and returns its values", function()
	local one, two = darken.run(sealed, IV, KEY)
	assert(one == 1 and two == "two", "darken.run returned " .. tostring(one) .. ", " .. tostring(two))
end)

test("darken.load returns the script loaded and not run", function()
	local script = darken.load(seal("error('ran', 0)"), IV, KEY)
	assert(type(script) == "function", "darken.load returned " .. tostring(script))
	local ok, err = pcall(script)
	assert(not ok and err == "ran", "the loaded script raised " .. tostring(err))
end)

test("darken.run runs an empty script, a ciphertext that is only its tag", function()
	local empty = seal("")
	assert(#empty == TAGLEN, "an empty script sealed to " .. #empty .. " bytes")
	assert(select("#", darken.run(empty, IV, KEY)) == 0, "an empty script returned values")
end)

test("darken.run raises EBADMSG for a wrong key", function()
	raises(MISMATCH, sealed, IV, KEY:upper())
end)

test("darken.run raises EBADMSG for a wrong IV", function()
	raises(MISMATCH, sealed, IV:upper(), KEY)
end)

test("darken.run raises EBADMSG for a flipped byte of the ciphertext", function()
	raises(MISMATCH, flip(sealed, 1), IV, KEY)
end)

test("darken.run raises EBADMSG for a flipped byte of the tag", function()
	raises(MISMATCH, flip(sealed, #sealed), IV, KEY)
end)

test("darken.run raises EBADMSG for a ciphertext cut short", function()
	raises(MISMATCH, sealed:sub(1, -2), IV, KEY)
	raises(MISMATCH, sealed:sub(1, TAGLEN - 1), IV, KEY)
end)

test("darken.run refuses an IV that is not 12 bytes", function()
	raises("IV must be 12 bytes", sealed, IV .. "iiii", KEY)
end)

test("darken.run refuses a key that is not 32 bytes", function()
	raises("key must be 32 bytes", sealed, IV, KEY:sub(2))
end)

test("darken.run raises the load error of a script that does not parse", function()
	raises("darken:1:", seal("return return"), IV, KEY)
end)

test("darken.run raises the load error of a chunk that does not load", function()
	raises("darken: bad binary format", seal("\27Lua"), IV, KEY)
end)

test("darken.run runs a stripped chunk and returns its values", function()
	local one, two = darken.run(seal(string.dump(load("return 1, 'two'"), true)), IV, KEY)
	assert(one == 1 and two == "two", "darken.run returned " .. tostring(one) .. ", " .. tostring(two))
end)

test("darken.run raises, and warns nothing, for a ciphertext past kmalloc's largest block", function()
	local ok, err = pcall(darken.run, string.rep("x", LARGE), IV, KEY)
	assert(not ok, "darken.run ran a ciphertext of " .. LARGE .. " bytes")
	assert(err:find("not enough memory", 1, true) or err:find(MISMATCH, 1, true), "darken.run raised " .. tostring(err))
end)

test("darken.run raises the error the script raises", function()
	raises("darkened", seal("error('darkened', 0)"), IV, KEY)
end)

