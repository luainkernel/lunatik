--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto acompress callback test (see acompress_callback.sh).

local acompress = require("crypto").acompress
local lib = require("tests.lib")

local char, rep = string.char, string.rep
local insert = table.insert

local ALGORITHM <const> = "lz4"
local COUNT <const> = 4
local OUTPUT <const> = 4096
local RAISE <const> = "ACOMPRESS callback raises on purpose"

HELD = {} -- global: a callback an asynchronous driver defers outlives the body that submitted it

local tfm, request
local raised, done, reused = false, 0, false

local function hold(object)
	insert(HELD, object)
	return object
end

local function original(index)
	return rep(char(64 + index), 128) .. " " .. index
end

local function onreuse()
	print("ACOMPRESS callback reusable")
end

-- the raising request is reused once both it and every round trip completed, in whichever order they arrive
local function reuse()
	if raised and done == COUNT and not reused then
		reused = true
		request:compress(original(1), OUTPUT, onreuse)
	end
end

local function ondecompress(index, plain)
	return function(err, output)
		if err ~= nil then
			print("ACOMPRESS callback failed " .. index .. ": " .. err)
		elseif output ~= plain then
			print("ACOMPRESS callback failed " .. index .. ": round-trip mismatch")
		else
			print("ACOMPRESS callback ok " .. index)
			done = done + 1
			reuse()
		end
	end
end

local function oncompress(index, plain)
	return function(err, compressed)
		if err ~= nil then
			print("ACOMPRESS callback failed " .. index .. ": " .. err)
			return
		end
		hold(tfm:request()):decompress(compressed, #plain, ondecompress(index, plain))
	end
end

local function raising()
	raised = true
	reuse()
	error(RAISE)
end

tfm = lib.alloc(acompress, ALGORITHM)
hold(tfm)

request = hold(tfm:request())
request:compress(original(1), OUTPUT, raising)

for index = 1, COUNT do
	local plain = original(index)
	hold(tfm:request()):compress(plain, OUTPUT, oncompress(index, plain))
end

