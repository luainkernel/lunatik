--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Helpers shared by the kernel-side test scripts, as tests/lib.sh is by the shell side.

local concat = table.concat
local traceback = debug.traceback

local lib = {}

local function log(what, ...)
	print(concat({what:upper(), ...}, "\t"))
end

--- Runs a test function and prints the result.
-- @tparam string test_name test name.
-- @tparam function func test function to run.
-- @usage test("Test Name", function() ... end)
function lib.test(test_name, func)
	local status, err = pcall(func)
	if status then
		log("pass", test_name)
	else
		log("fail", test_name, err, "\n" .. traceback())
	end
end

--- Allocates a crypto object, raising "the kernel serves no <name>" where the constructor raises ENOENT, which is how
-- the crypto API answers for an algorithm no provider serves; tests/lib.sh's served_case skips a case on the message.
-- @tparam function new constructor, such as `crypto.skcipher`.
-- @tparam string name algorithm name.
-- @return the object `new` returns.
-- @usage local gcm = lib.alloc(crypto.aead, "gcm(aes)")
function lib.alloc(new, name)
	local ok, object = pcall(new, name)
	if not ok then
		error(object == "ENOENT" and "the kernel serves no " .. name or object, 0)
	end
	return object
end

--- Asserts that a call raises an error that contains the expected text.
-- @tparam string expected text the error carries, such as an errno's name.
-- @tparam function f function to call.
-- @param ... arguments to `f`.
-- @usage lib.raises("EINVAL", cipher.setkey, cipher, "")
function lib.raises(expected, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, "no raise where " .. expected .. " was expected")
	err = tostring(err)
	assert(err:find(expected, 1, true), "raised " .. err .. " where " .. expected .. " was expected")
end

return lib

