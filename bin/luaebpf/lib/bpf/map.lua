--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares a map in a program file.
--
-- The compile-time twin of the kernel `bpf.map`: the same names and the same spec vocabulary,
-- producing a BTF-defined map in the object instead of opening a pinned one. A map needs a name
-- whether or not a compiled function references it, since that is what the loader pins it under
-- and what a kernel script opens it by.
--
-- Inside a compiled function a map is a table proxy with the kernel module's semantics:
-- indexing looks up, assignment updates, assigning `nil` deletes. A lookup has the type "value
-- or nil", and the translator refuses to use it as a number until the function has tested it,
-- which is what the verifier requires of the pointer underneath. A `struct` value spec yields a
-- read-only proxy of fields rather than a number, read by field name, as the kernel module decodes
-- such a value into a table keyed by the layout's names; an index into it is refused, and so is a
-- field wider than a byte on a kernel without efficient unaligned access, as a packet read is.
-- @module bpf.map
-- @usage
-- local map = require("bpf.map")
--
-- local flows = map.hash("flows", {key = "I4", value = "I4", entries = 65536})
-- local hits  = map.array("hits", {key = "I4", value = "I8", entries = 1})

local maps     = require("luaebpf.maps")
local map_type = require("linux.bpf").map_type

local pack, packsize, unpack = string.pack, string.packsize, string.unpack
local mathtype               = math.type

-- the map types a program file may declare, under the name of the constructor that declares them
local kinds = {hash = map_type.HASH, array = map_type.ARRAY, lru_hash = map_type.LRU_HASH}

-- eBPF loads and stores one, two, four or eight bytes, so whatever a compiled function reads as
-- one number is one of those widths
local loadable = {[1] = true, [2] = true, [4] = true, [8] = true}

local MAXENTRIES <const> = 0xffffffff -- max_entries is a __u32
local INDEX      <const> = 4          -- array_map_alloc_check refuses any other key_size
local CALLER     <const> = 2          -- each constructor tail-calls declare, so this is its caller
local CHECK      <const> = CALLER + 1 -- a check declare calls is one frame below it

-- BTF names a map's attributes through a struct of that name, and btf_name_valid_identifier
-- refuses anything else, so the object either fails to load or loses the BTF its lines live in
local IDENTIFIER <const> = "^[%a_][%w_]*$"

local map = {}

local function measure(spec)
	local size = packsize(spec)
	return size, select("#", unpack(spec, ("\0"):rep(size))), unpack(spec, ("\xff"):rep(size))
end

-- a spec the kernel reads as one fixed-size integer: the format itself says how wide it is, and
-- all ones comes back negative exactly when it is signed. Protected, since a format Lua can
-- size but not read back raises rather than answering.
local function scalar(spec)
	if type(spec) ~= "string" then
		return nil
	end
	local read, size, values, value = pcall(measure, spec)
	if not read or values ~= 2 or mathtype(value) ~= "integer" then
		return nil
	end
	-- padding packs as zeros, so all ones packs back whole only where the integer fills the spec
	if pack(spec, value) ~= ("\xff"):rep(size) then
		return nil
	end
	local signed = value < 0
	-- an eBPF load and store take the host's byte order, and nothing here swaps
	local native = pack(spec, 1) == pack((signed and "=i" or "=I") .. size, 1)
	return {format = spec, size = size, signed = signed, native = native}
end

-- the width in a spec that no eBPF load covers, or nil where every one of them is covered
local function unreadable(spec)
	for _, field in pairs(spec.fields or {spec}) do
		if not loadable[field.size] then
			return field.size
		end
	end
end

-- a struct codec, whose layout says where every field sits and how wide it is
local function record(spec)
	if type(spec) ~= "table" or spec.pack == nil or spec.layout == nil then
		return nil
	end
	local fields = {}
	for _, field in ipairs(spec.layout.fields) do
		fields[field.name] = field
	end
	return {size = spec.size, fields = fields, native = true}
end

local function named(kind, name, spec)
	if type(name) ~= "string" or type(spec) ~= "table" or mathtype(spec.entries) ~= "integer" then
		error(("map.%s takes a name and a spec"):format(kind), CHECK)
	end
	if not name:match(IDENTIFIER) then
		error(("a map name is a C identifier, not '%s'"):format(name), CHECK)
	end
end

local function codecs(spec)
	local key = scalar(spec.key)
	if key == nil then
		error("a map key spec packs one value", CHECK)
	end
	local value = scalar(spec.value) or record(spec.value)
	if value == nil then
		error("a map value spec packs one value or is a struct codec", CHECK)
	end
	return key, value
end

local function readable(spec, key, value)
	local foreign = not key.native and spec.key or not value.native and spec.value
	if foreign then
		error(("a map is read in the host's byte order, not '%s'"):format(foreign), CHECK)
	end
	local width = unreadable(key) or unreadable(value)
	if width ~= nil then
		error(("a map reads 1, 2, 4 or 8 bytes at a time, not %d"):format(width), CHECK)
	end
end

local function sized(kind, key, entries)
	if kind == "array" and key.size ~= INDEX then
		error(("an array map is keyed by %d bytes, not %d"):format(INDEX, key.size), CHECK)
	end
	if entries < 1 or entries > MAXENTRIES then
		error(("a map holds between 1 and %d entries, not %d"):format(MAXENTRIES, entries), CHECK)
	end
end

local function declare(kind, name, spec)
	named(kind, name, spec)
	local key, value = codecs(spec)
	readable(spec, key, value)
	sized(kind, key, spec.entries)
	local declared = maps.declare{name = name, type = kinds[kind], entries = spec.entries,
		key = key, value = value}
	if declared == nil then
		error(("'%s' is declared twice"):format(name), CALLER)
	end
	return declared
end

---
-- Declaring a map in a program file.
-- @section declare

---
-- Declares a hash map in a program file, which `lunatik bpf` compiles.
-- @function bpf.map.hash
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`; `key` is a `string.pack` format of one fixed-size
--   integer, `value` is one of those or a `struct` codec, and `entries` is the map's capacity
-- @treturn table the declared map, a table proxy inside a compiled function
-- @raise `map.hash takes a name and a spec`, `a map name is a C identifier, not '<name>'`, `a
--   map key spec packs one value`, `a map value spec packs one value or is a struct codec`, `a
--   map is read in the host's byte order, not '<spec>'`, `a map reads 1, 2, 4 or 8 bytes at a
--   time, not <n>`, `a map holds between 1 and 4294967295 entries, not <n>`, or `'<name>' is
--   declared twice`
function map.hash(name, spec)
	return declare("hash", name, spec)
end

---
-- Declares an array map in a program file, whose keys are its `u32` indices.
-- @function bpf.map.array
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`, as `hash` takes, the key four bytes wide
-- @treturn table the declared map
-- @raise as `hash` raises, plus `an array map is keyed by 4 bytes, not <n>`
function map.array(name, spec)
	return declare("array", name, spec)
end

---
-- Declares an LRU hash map in a program file.
-- @function bpf.map.lru_hash
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`, as `hash` takes
-- @treturn table the declared map
-- @raise as `hash` raises
function map.lru_hash(name, spec)
	return declare("lru_hash", name, spec)
end

return map

