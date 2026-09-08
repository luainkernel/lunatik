--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the failed-resize test (see resize_atomic.sh).

local data = require("data")

local BIG    <const> = 1 << 26 -- vmalloc-backed where MAX_PAGE_ORDER + PAGE_SHIFT is under 26; the .sh skips elsewhere
local BIGGER <const> = 1 << 27
local MARK   <const> = 0x5a

local buffer = data.new(BIG)
buffer:setbyte(0, MARK)

local function grow()
	local ok, err = pcall(buffer.resize, buffer, BIGGER)
	assert(not ok, "the atomic resize should have failed")
	assert(err:match("not enough memory"), "data:resize raised something else: " .. err)
	assert(#buffer == BIG, "a failed resize changed the size to " .. #buffer)
	assert(buffer:getbyte(0) == MARK, "a failed resize dropped the buffer")
end

return grow

