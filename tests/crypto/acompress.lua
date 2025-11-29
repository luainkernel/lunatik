--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local acomp = require("crypto.acompress")
local completion = require("completion")
local test = require("util").test

local function async_operation(op)
	return function(tfm, inputs)
		local results = {}
		local done = completion.new()
		local count = 0
		local total = #inputs
		-- keep requests alive until completion
		local reqs = {}

		local function check_done()
			count = count + 1
			if count == total then
				done:complete()
			end
		end

		for i, input in ipairs(inputs) do
			local req = tfm:request()
			reqs[i] = req
			req[op](req, input, 4096, function(err, data)
				results[i] = {err = err, data = data}
				check_done()
			end)
		end

		if total > 0 then
			local ok, why = done:wait()
			assert(ok, "Wait failed: " .. tostring(why))
		end
		return results
	end
end

local async_compress = async_operation("compress")
local async_decompress = async_operation("decompress")

test("ACOMP compress async concurrent", function()
	local tfm = acomp.new("lz4")
	local inputs = {"hello world 1", "hello world 2"}
	
	local results = async_compress(tfm, inputs)

	assert(#results == 2, "Expected 2 results")
	assert(results[1].err == 0, "Req1 failed")
	assert(results[2].err == 0, "Req2 failed")
	assert(results[1].data ~= results[2].data, "Results should differ")
	assert(#results[1].data > 0, "Res1 empty")
	assert(#results[2].data > 0, "Res2 empty")
end)

test("ACOMP decompress async concurrent", function()
	local tfm = acomp.new("lz4")
	local inputs = {"data one", "data two"}

	-- Prepare compressed data concurrently
	local compressed_results = async_compress(tfm, inputs)
	for i, res in ipairs(compressed_results) do
		assert(res.err == 0, "Prep compress " .. i .. " failed")
		compressed_results[i] = res.data
	end

	-- Concurrent decompression
	local results = async_decompress(tfm, compressed_results)

	assert(#results == 2, "Expected 2 results")
	assert(results[1].data == "data one", "Res1 mismatch")
	assert(results[2].data == "data two", "Res2 mismatch")
end)

