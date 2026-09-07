--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the resume_results test (see resume_results.sh).

local lunatik = require("lunatik")
local data    = require("data")

local ANSWER <const> = 42
local FIRST <const> = 1
local SECOND <const> = 2
local MANY <const> = 32

local function assert_error(fn, pattern)
	local ok, err = pcall(fn)
	assert(not ok, "expected error but got none")
	assert(err:find(pattern), "unexpected error: " .. tostring(err))
end

local rt = lunatik.runtime("tests/runtime/resume_results_recv")

-- a value that is not an object never crosses, and leaves the runtime untouched
assert_error(function() rt:resume(ANSWER) end, "invalid object")

-- one object yielded, on a resume carrying two arguments: the value comes off the resumed stack
local one = rt:resume(data.new(FIRST), data.new(SECOND))
assert(one:getbyte(0) == ANSWER, "resume did not return the object the script yielded")

-- two objects yielded, in the order the script yielded them
local first, second = rt:resume()
assert(first:getbyte(0) == FIRST and second:getbyte(0) == SECOND, "resume reordered the yielded objects")

-- more objects than the LUA_MINSTACK slots a C function is entered with, in and back out
local sent = {}
for i = 1, MANY do
	table.insert(sent, data.new(i))
end
local back = table.pack(rt:resume(table.unpack(sent)))
assert(back.n == MANY, "resume returned " .. back.n .. " of the " .. MANY .. " objects the script yielded")
for i = 1, MANY do
	assert(#back[i] == i, "resume reordered the yielded objects at " .. i)
end

-- a yielded value that is not an object, with the runtime still suspended after it
assert_error(function() rt:resume() end, "invalid object")

-- a yielded SINGLE object, with the runtime still suspended after it
assert_error(function() rt:resume() end, "cannot share SINGLE object")

-- the object the script returns
local last = rt:resume()
assert(last:getbyte(0) == ANSWER, "resume did not return the object the script returned")

-- the runtime is dead once its body has returned
assert_error(function() rt:resume() end, "cannot resume dead coroutine")

