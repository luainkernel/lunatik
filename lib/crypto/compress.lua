--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Synchronous compression API on top of the asynchronous acompress interface.
-- This module provides a synchronous, high-level API, implemented on top of
-- the low-level `crypto.acompress` and `completion` modules. It exposes the
-- same interface as the legacy `crypto.comp` (removed from the kernel in
-- 6.15): `new(algname)`, `:compress(data, max_len)`, `:decompress(data, max_len)`.
-- @classmod crypto.compress

local acompress = require("crypto").acompress
local completion = require("completion")

local COMPRESS = {}
COMPRESS.__index = COMPRESS

--- Creates a new compression object.
-- @function new
-- @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate", "lzo")
-- @treturn COMPRESS A new compression object
-- @raise Error if the compression algorithm is not available
-- @usage
--   local compress = require("crypto.compress").new("lz4")
function COMPRESS.new(algname)
	local tfm = acompress(algname)
	return setmetatable({ tfm = tfm, req = tfm:request() }, COMPRESS)
end

local function operation(name)
	return function(self, data, max_len)
		local done = completion.new()
		local result, output

		self.req[name](self.req, data, max_len, function(err, out)
			result = err
			output = out
			done:complete()
		end)

		local ok, why = done:wait()
		if not ok then
			error(name .. " wait failed: " .. tostring(why))
		end
		if result then
			error(result, 0)
		end
		return output
	end
end

--- Compresses data synchronously.
-- @function compress
-- @tparam string data input data to compress
-- @tparam integer max_len maximum expected output length
-- @treturn string compressed data
-- @raise errno name (e.g. "EINVAL") on failure
COMPRESS.compress = operation("compress")

--- Decompresses data synchronously.
-- @function decompress
-- @tparam string data input data to decompress
-- @tparam integer max_len maximum expected output length
-- @treturn string decompressed data
-- @raise errno name (e.g. "EINVAL") on failure
COMPRESS.decompress = operation("decompress")

return COMPRESS
