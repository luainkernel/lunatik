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
-- which is what the verifier requires of the pointer underneath.
-- @module bpf.map
-- @usage
-- local map = require("bpf.map")
--
-- local flows = map.hash("flows", {key = "I4", value = "I4", entries = 65536})
-- local hits  = map.array("hits", {key = "I4", value = "I8", entries = 1})

local bpf  = require("linux.bpf")
local maps = require("luaebpf.maps")

local packsize, unpack = string.packsize, string.unpack

-- the map types a program file may declare, under the name of the constructor that declares them
local kinds = {hash = bpf.MAP_TYPE_HASH, array = bpf.MAP_TYPE_ARRAY, lru_hash = bpf.MAP_TYPE_LRU_HASH}

local map = {}

-- a spec the kernel reads as one fixed-size number: the format itself says how wide it is, and
-- all ones comes back negative exactly when it is signed
local function scalar(spec)
	if type(spec) ~= "string" then
		return nil
	end
	local sized, size = pcall(packsize, spec)
	if not sized or select("#", unpack(spec, ("\0"):rep(size))) ~= 2 then
		return nil
	end
	local value = unpack(spec, ("\xff"):rep(size))
	if type(value) ~= "number" then
		return nil
	end
	return {size = size, signed = value < 0}
end

local function declare(kind, name, spec)
	if type(name) ~= "string" or type(spec) ~= "table" or type(spec.entries) ~= "number" then
		error(("map.%s takes a name and a spec"):format(kind), 3)
	end
	local key = scalar(spec.key)
	if key == nil then
		error("a map key spec packs one value", 3)
	end
	local value = scalar(spec.value)
	if value == nil then
		error("a map value spec packs one value", 3)
	end
	local declared = maps.declare{name = name, type = kinds[kind], entries = spec.entries,
		key = key, value = value}
	if declared == nil then
		error(("'%s' is declared twice"):format(name), 3)
	end
	return declared
end

---
-- Declares a hash map.
-- @function bpf.map.hash
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`; `key` and `value` are `string.pack` formats of one
--   fixed-size number each, and `entries` is the map's capacity
-- @treturn table the declared map, a table proxy inside a compiled function
-- @raise `map.hash takes a name and a spec`, `a map key spec packs one value`, `a map value
--   spec packs one value`, or `'<name>' is declared twice`
function map.hash(name, spec)
	return declare("hash", name, spec)
end

---
-- Declares an array map, whose keys are its `u32` indices.
-- @function bpf.map.array
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`, as `hash` takes
-- @treturn table the declared map
-- @raise as `hash` raises
function map.array(name, spec)
	return declare("array", name, spec)
end

---
-- Declares an LRU hash map.
-- @function bpf.map.lru_hash
-- @tparam string name what the object calls it, and what the loader pins it under
-- @tparam table spec `{key, value, entries}`, as `hash` takes
-- @treturn table the declared map
-- @raise as `hash` raises
function map.lru_hash(name, spec)
	return declare("lru_hash", name, spec)
end

return map

