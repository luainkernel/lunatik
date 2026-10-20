--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Builds a `set` from a set image, a file a tool writes in userspace.
--
-- A set image is the set's own arrays behind a 16-byte header, so `set.fromdata` builds the set over the
-- bytes the file was read into, and nothing is copied, sorted or indexed in the kernel: a set costs
-- its file's size. The file is little-endian throughout:
--
-- - a 16-byte header: the ASCII bytes `LSET`; a u16 version, 1; u16 flags, whose bit 0 says the
--   file carries labels and whose other bits are 0; a u32 `n`, the number of members; and a u32
--   `len`, the bytes the members take;
-- - u32 `off[n+1]`, member `i` being bytes `off[i]` up to `off[i+1]` of the members;
-- - u32 `labels[n]`, only when bit 0 is set, each in `[1, 2^32)`; the members of a file without
--   labels carry 1;
-- - the members, concatenated without separators in `len` bytes, strictly increasing compared
--   byte by byte, the shorter first on a tie, so sorted and unique.
--
-- Its size is exactly `16 + 4(n+1) + 4n + len`, the `4n` only with labels. This module checks the
-- header and the size, and `set.fromdata` makes no lookup read outside the file: members out of order
-- or repeated, offsets that decrease or reach past it and a label of 0 make the lookups answer wrong,
-- the error of the tool that wrote the file. A later layout takes another version; this one reads
-- version 1.
-- @module set.image
-- @see set
-- @usage
-- local image = require("set.image")
--
-- local blocked = image.load("/etc/lunatik/blocked.set", 64 << 20)
-- local label = blocked:match("ads.example.com")

local data = require("data")
local set  = require("set")

local unpack, packsize = string.unpack, string.packsize

local HEADER  <const> = "<c4I2I2I4I4"
local SIZE    <const> = packsize(HEADER)
local MAGIC   <const> = "LSET"
local VERSION <const> = 1
local LABELED <const> = 1
local U32     <const> = 4

local image = {}

-- the members, their bytes and whether labels follow, or nil and the rule the header breaks
local function readheader(d)
	if #d < SIZE or d:getstring(0, #MAGIC) ~= MAGIC then
		return nil, "not a set image"
	end
	local _, version, flags, n, len = unpack(HEADER, d:getstring(0, SIZE))
	if version ~= VERSION then
		return nil, "unsupported version"
	elseif (flags & ~LABELED) ~= 0 then
		return nil, "unknown flags"
	end
	return {n = n, len = len, labeled = (flags & LABELED) ~= 0}
end

-- where set.fromdata finds the arrays the header declares, or nil and the rule when d is not their size
local function locate(d, header)
	local labels = SIZE + U32 * (header.n + 1)
	local blob = labels + (header.labeled and U32 * header.n or 0)
	if #d ~= blob + header.len then
		return nil, "size mismatch"
	end
	return {n = header.n, offsets = SIZE, labels = header.labeled and labels or nil, blob = blob}
end

---
-- Reads a set image and builds a set over it, in one allocation of the file's size.
-- @function load
-- @tparam string path the file.
-- @tparam integer maxbytes the largest file it reads, in bytes, from 1 up to `INT_MAX`.
-- @treturn set the built set.
-- @raise what `data.load` raises, its errno among them; after the path and `: `, the rule the file
--   breaks: `not a set image` for one shorter than the header or without its magic, `unsupported
--   version`, `unknown flags` or `size mismatch`; or what `set.fromdata` raises.
function image.load(path, maxbytes)
	local d = data.load(path, maxbytes)
	local header, rule = readheader(d)
	local layout
	if header ~= nil then
		layout, rule = locate(d, header)
	end
	if layout == nil then
		error(path .. ": " .. rule, 2)
	end
	return set.fromdata(d, layout)
end

return image

