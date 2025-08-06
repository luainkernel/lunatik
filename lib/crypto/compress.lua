--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Synchronous compression API using Linux kernel acompress (async) interface.
-- This module provides a synchronous, high-level API, but implemented on top
-- of the low-level `crypto.acompress` and `completion` modules.
--
-- @module crypto.compress

local acomp = require("crypto.acompress")
local completion = require("completion")

--- @type COMPRESS
local COMPRESS = {}
COMPRESS.__index = COMPRESS

--- Creates a new compression object.
-- @function new
-- @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate", "lzo")
-- @treturn COMPRESS A new compression object that can be used for compress/decompress operations
-- @raise Error if the compression algorithm is not available or cannot be initialized
-- @usage
--   local compress = require("crypto.compress").new("lz4")
-- @within compress
function COMPRESS.new(algname)
	return setmetatable({ tfm = acomp.new(algname) }, COMPRESS)
end

local function operation(name)
	return function(self, data, max_output_len)
		local done = completion.new()
		local result, output

		self.tfm[name](self.tfm, data, max_output_len, function(err, out)
			result = err
			output = out
			done:complete()
		end)

		local ok, why = done:wait()
		if not ok then
			error(name .. " wait failed: " .. tostring(why))
		end
		if result ~= 0 then
			error(-result)
		end
		return output
	end
end

--- Compresses data synchronously.
-- @function compress
-- @tparam string data input data to compress
-- @tparam integer max_output_len maximum expected output length
-- @treturn string compressed data
-- @raise error if compression fails or wait operation fails
-- @usage
--   local c = require("crypto.compress").new("lz4")
--   local compressed = c:compress("hello world", 64)
COMPRESS.compress = operation("compress")

--- Decompresses data synchronously.
-- @function decompress
-- @tparam string data input data to decompress
-- @tparam integer max_output_len maximum expected output length
-- @treturn string decompressed data
-- @raise error if decompression fails or wait operation fails
-- @usage
--   local c = require("crypto.compress").new("lz4")
--   local decompressed = c:decompress(compressed_data, 1024)
COMPRESS.decompress = operation("decompress")

return COMPRESS

