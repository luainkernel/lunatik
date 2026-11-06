--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto acompress callback test (see acompress_callback.sh).

local acompress = require("crypto").acompress
local lib = require("tests.lib")

local char, rep = string.char, string.rep
local concat, insert = table.concat, table.insert

local ALGORITHM <const> = "lz4"
local COUNT <const> = 4
local OUTPUT <const> = 4096
local PAGE <const> = 4096
local SPAN <const> = 3 * PAGE
local PAYLOAD <const> = rep("abcdefghijklmnopqrstuvwxyz", 100)
local EINVAL <const> = "EINVAL"
local RAISE <const> = "ACOMPRESS callback raises on purpose"

HELD = {} -- global: a callback an asynchronous driver defers outlives the body that submitted it

local tfm, request
local raised, done, reused = false, 0, false

local function hold(object)
	insert(HELD, object)
	return object
end

-- incompressible bytes, so the compression keeps the page spanning of the input
local function noise(length)
	local bytes, seed = {}, 1
	for _ = 1, length do
		seed = (seed * 1103515245 + 12345) % 2147483648
		insert(bytes, char((seed >> 16) % 256))
	end
	return concat(bytes)
end

local SPANNING <const> = noise(SPAN)

local function onreuse()
	print("ACOMPRESS callback reusable")
end

local function failed(name, reason)
	print("ACOMPRESS callback failed " .. name .. ": " .. reason)
end

-- the raising request is reused once both it and every case completed, in whichever order they arrive
local function reuse()
	if raised and done == COUNT and not reused then
		reused = true
		request:compress(PAYLOAD, OUTPUT, onreuse)
	end
end

local function ok(name)
	print("ACOMPRESS callback ok " .. name)
	done = done + 1
	reuse()
end

local function ondecompress(name, plain)
	return function(err, output)
		if err ~= nil then
			failed(name, err)
		elseif output ~= plain then
			failed(name, "round-trip mismatch")
		else
			ok(name)
		end
	end
end

local function oncompress(name, plain, max_len)
	return function(err, compressed)
		if err ~= nil then
			failed(name, err)
			return
		end
		hold(tfm:request()):decompress(compressed, max_len, ondecompress(name, plain))
	end
end

-- a decompression into a buffer one byte short answers the errno and no output
local function onsmall(err, output)
	if err ~= EINVAL then
		failed("small", err or "a buffer one byte short was accepted")
	elseif output ~= nil then
		failed("small", "a failed decompression returned output")
	else
		ok("small")
	end
end

local function oncompress_small(err, compressed)
	if err ~= nil then
		failed("small", err)
		return
	end
	hold(tfm:request()):decompress(compressed, #PAYLOAD - 1, onsmall)
end

local function raising()
	raised = true
	reuse()
	error(RAISE)
end

tfm = lib.alloc(acompress, ALGORITHM)
hold(tfm)

request = hold(tfm:request())
request:compress(PAYLOAD, OUTPUT, raising)

hold(tfm:request()):compress(PAYLOAD, OUTPUT, oncompress("roundtrip", PAYLOAD, #PAYLOAD))
hold(tfm:request()):compress(PAYLOAD, OUTPUT, oncompress("larger", PAYLOAD, #PAYLOAD + 10))
hold(tfm:request()):compress(PAYLOAD, OUTPUT, oncompress_small)
hold(tfm:request()):compress(SPANNING, SPAN * 2, oncompress("spanning", SPANNING, SPAN))

