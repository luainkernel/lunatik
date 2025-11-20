--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local acomp = require("crypto.acompress")
local completion = require("completion")
local test = require("util").test

test("ACOMP compress async concurrent", function()
	local tfm = acomp.new("lz4")
	local req1 = tfm:request()
	local req2 = tfm:request()
	local done = completion.new()
	local count = 0
	local res1, res2

	local function check_done()
		count = count + 1
		if count == 2 then
			done:complete()
		end
	end

	local function cb1(err, data)
		res1 = {err = err, data = data}
		check_done()
	end

	local function cb2(err, data)
		res2 = {err = err, data = data}
		check_done()
	end

	local data1 = "hello world 1"
	local data2 = "hello world 2"

	req1:compress(data1, 100, cb1)
	req2:compress(data2, 100, cb2)
	
	local ok, why = done:wait()
	assert(ok, "Wait failed: " .. tostring(why))
	
	assert(res1.err == 0, "Req1 failed")
	assert(res2.err == 0, "Req2 failed")
	assert(res1.data ~= res2.data, "Results should differ")
	assert(#res1.data > 0, "Res1 empty")
	assert(#res2.data > 0, "Res2 empty")
end)

test("ACOMP decompress async concurrent", function()
	local tfm = acomp.new("lz4")
	local req1 = tfm:request()
	local req2 = tfm:request()
	local done = completion.new()
	local cdata1, cdata2
	local count = 0

	-- Prepare compressed data concurrently
	local function check_prep_done()
		count = count + 1
		if count == 2 then done:complete() end
	end

	req1:compress("data one", 100, function(err, data)
		assert(err == 0, "Prep compress 1 failed")
		cdata1 = data
		check_prep_done()
	end)

	req2:compress("data two", 100, function(err, data)
		assert(err == 0, "Prep compress 2 failed")
		cdata2 = data
		check_prep_done()
	end)
	
	local ok, why = done:wait()
	assert(ok, "Prep wait failed: " .. tostring(why))

	-- Concurrent decompression
	done = completion.new()
	count = 0
	local res1, res2

	local function check_done()
		count = count + 1
		if count == 2 then done:complete() end
	end

	req1:decompress(cdata1, 100, function(err, data)
		res1 = {err = err, data = data}
		check_done()
	end)

	req2:decompress(cdata2, 100, function(err, data)
		res2 = {err = err, data = data}
		check_done()
	end)

	ok, why = done:wait()
	assert(ok, "Wait failed")
	assert(res1.data == "data one", "Res1 mismatch")
	assert(res2.data == "data two", "Res2 mismatch")
end)

