--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Buffer checks shared by the data zeroing scripts (see run.sh).

local data = require("data")

local insert = table.insert
local find, rep = string.find, string.rep

local MARK  <const> = "\x5a"
local BATCH <const> = 32 -- buffers poisoned and freed together, so the next round has blocks to take back

local zeroing = {}

local function checkzeroed(buffer, offset, length, what)
	local stale = find(buffer:getstring(offset, length), "[^\0]")
	if stale then
		error(what .. " read a byte nobody wrote, at offset " .. offset + stale - 1, 2)
	end
end

function zeroing.checknew(size, mode)
	local buffer = data.new(size, mode)
	checkzeroed(buffer, 0, size, "data.new(" .. size .. ")")
	return buffer
end

-- a round allocates over the blocks the round before poisoned and freed, which is what an
-- unzeroed data.new reads back
function zeroing.newrounds(rounds, size, mode)
	local poison = rep(MARK, size)

	for _ = 1, rounds do
		local buffers = {}
		for _ = 1, BATCH do
			local buffer = zeroing.checknew(size, mode)
			buffer:setstring(0, poison)
			insert(buffers, buffer)
		end
		buffers = nil
		collectgarbage("collect") -- __gc frees what the next round allocates over
	end
end

function zeroing.growrounds(rounds, size, newsize)
	local kept = rep(MARK, size)
	local poison = rep(MARK, newsize)
	local what = "data:resize(" .. size .. " -> " .. newsize .. ")"

	for _ = 1, rounds do
		local buffers = {}
		for _ = 1, BATCH do
			local buffer = data.new(size)
			buffer:setstring(0, kept)
			buffer:resize(newsize)
			assert(#buffer == newsize, what .. " did not take, got " .. #buffer)
			assert(buffer:getstring(0, size) == kept, what .. " lost the bytes it had")
			checkzeroed(buffer, size, newsize - size, what)
			buffer:setstring(0, poison)
			insert(buffers, buffer)
		end
		buffers = nil
		collectgarbage("collect")
	end
end

-- a shrink keeps the block, so the bytes a growth back into it uncovers are this buffer's own:
-- the one case that needs no allocator luck
function zeroing.checkregrow(size, small)
	local kept = rep(MARK, small)
	local what = "data:resize(" .. size .. " -> " .. small .. " -> " .. size .. ")"
	local buffer = data.new(size)

	buffer:setstring(0, rep(MARK, size))
	buffer:resize(small)
	assert(#buffer == small, what .. " did not shrink, got " .. #buffer)
	assert(buffer:getstring(0, small) == kept, what .. " lost the bytes the shrink keeps")

	buffer:resize(size)
	assert(#buffer == size, what .. " did not grow back, got " .. #buffer)
	assert(buffer:getstring(0, small) == kept, what .. " lost the bytes the growth keeps")
	checkzeroed(buffer, small, size - small, what)
end

return zeroing

