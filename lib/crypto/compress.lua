--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Synchronous compression on top of the asynchronous acompress interface.
-- This module exposes the same interface as the legacy `crypto.comp` (whose kernel API was removed
-- in 6.15): `new(algname)`, `:compress(data, max_len)`, `:decompress(data, max_len)`, `:algname()`
-- and `:close()`.
-- @classmod crypto.compress

local acompress = require("crypto").acompress

local compress = {}
compress.__name = "crypto.compress"
compress.__index = compress

--- Creates a new compression object.
-- @function new
-- @tparam string algname compression algorithm name (e.g., "lz4").
-- @treturn compress a new compression object.
-- @usage local c = require("crypto.compress").new("lz4")
function compress.new(algname)
	local tfm = acompress(algname)
	return setmetatable({tfm = tfm, req = tfm:request()}, compress)
end

--- Returns the driver-independent name of the algorithm the transform was allocated with.
-- @function algname
-- @treturn string
function compress:algname()
	return self.tfm:algname()
end

--- Releases the transform and its request.
-- It also runs when a to-be-closed variable holding the instance goes out of scope. Calling it
-- again does nothing, and every other method raises "closed object" afterwards.
-- @function close
function compress:close()
	self.req:close()
	self.tfm:close()
end

compress.__close = compress.close

--- Compresses data synchronously.
-- @function compress
-- @tparam string data input data to compress.
-- @tparam integer max_len maximum size of the compressed output.
-- @treturn string compressed data.
-- @raise errno name (e.g. "EINVAL") on failure.
function compress:compress(data, max_len)
	return self.req:compress(data, max_len)
end

--- Decompresses data synchronously.
-- @function decompress
-- @tparam string data compressed input.
-- @tparam integer max_len maximum size of the decompressed output.
-- @treturn string decompressed data.
-- @raise errno name (e.g. "EINVAL") on failure.
function compress:decompress(data, max_len)
	return self.req:decompress(data, max_len)
end

return compress

