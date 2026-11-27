--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Writes a raw BTF in the other byte order, for luaebpf_swapped (see common.sh).

local pack, unpack = string.pack, string.unpack
local insert       = table.insert

local MAGIC <const> = 0xeb9f
local WORD  <const> = 4

local file = assert(io.open(arg[1], "rb"))
local bytes = file:read("a")
file:close()

local from = unpack("<I2", bytes) == MAGIC and "<" or ">"
local to = from == "<" and ">" or "<"
local hdrlen, typeoff, typelen = unpack(from .. "I4I4I4", bytes, 5)
local types = hdrlen + typeoff
local out = {pack(to .. "I2", MAGIC), bytes:sub(3, 4)}

local function swap(first, last)
	for at = first, last, WORD do
		insert(out, pack(to .. "I4", (unpack(from .. "I4", bytes, at))))
	end
end

swap(5, hdrlen)
insert(out, bytes:sub(hdrlen + 1, types))
swap(types + 1, types + typelen)
insert(out, bytes:sub(types + typelen + 1))
file = assert(io.open(arg[2], "wb"))
assert(file:write(table.concat(out)))
assert(file:close())

