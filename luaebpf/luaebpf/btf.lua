--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The `.BTF` and `.BTF.ext` sections: a `FUNC` and a `FUNC_PROTO` per compiled function, and
-- the `func_info` and `line_info` records that let the verifier's log quote the Lua source.
--
-- In the object an `insn_off` is a byte offset into its section; the kernel takes an index in
-- instructions, and libbpf converts on the way in.
-- @module luaebpf.btf

local class = require("class")

local pack   = string.pack
local concat = table.concat
local insert = table.insert

local MAGIC   <const> = 0xeb9f
local VERSION <const> = 1
local HDRLEN  <const> = 24
local EXTLEN  <const> = 32
local FUNCREC <const> = 8
local LINEREC <const> = 16

local KIND_INT        <const> = 1
local KIND_PTR        <const> = 2
local KIND_ARRAY      <const> = 3
local KIND_STRUCT     <const> = 4
local KIND_FUNC       <const> = 12
local KIND_FUNC_PROTO <const> = 13
local KIND_VAR        <const> = 14
local KIND_DATASEC    <const> = 15
local SIGNED          <const> = 1
local STATIC          <const> = 0
local GLOBAL          <const> = 1
local ALLOCATED       <const> = 1 -- BTF_VAR_GLOBAL_ALLOCATED
local BYTE            <const> = 8
local WORD            <const> = 8 -- a map attribute is a pointer, which is what libbpf reads

local btf = {}

--- Function linkage, as `BTF_FUNC_*` names it.
-- @table luaebpf.btf.linkage
btf.linkage = {STATIC = STATIC, GLOBAL = GLOBAL}

---
-- A BTF section under construction.
-- @type luaebpf.btf.types
local types = class{}

local function typeinfo(kind, vlen)
	return (kind << 24) | vlen
end

---
-- A fresh BTF section carrying the two integer types every compiled function is written in.
-- @function luaebpf.btf.new
-- @treturn luaebpf.btf.types
function btf.new()
	local self = types:new{records = {}, n = 0, strings = {"\0"}, offsets = {[""] = 0}, length = 1}
	self.int = self:integer("int", 4, 32)
	self.long = self:integer("long", 8, 64)
	return self
end

---
-- Interns a string in the BTF string section.
-- @function luaebpf.btf.types:string
-- @tparam string name
-- @treturn integer its offset
function types:string(name)
	local at = self.offsets[name]
	if at ~= nil then
		return at
	end
	at = self.length
	insert(self.strings, name .. "\0")
	self.offsets[name] = at
	self.length = at + #name + 1
	return at
end

---
-- Appends a raw type record.
-- @function luaebpf.btf.types:add
-- @tparam string record
-- @treturn integer its type id
function types:add(record)
	insert(self.records, record)
	self.n = self.n + 1
	return self.n
end

---
-- A signed integer type.
-- @function luaebpf.btf.types:integer
-- @tparam string name
-- @tparam integer size in bytes
-- @tparam integer bits
-- @treturn integer its type id
function types:integer(name, size, bits)
	return self:add(pack("<I4I4I4I4", self:string(name), typeinfo(KIND_INT, 0), size,
		(SIGNED << 24) | bits))
end

---
-- A function and the prototype under it. Parameters are named, as the kernel's BTF checker
-- expects of a prototype that names any of them.
-- @function luaebpf.btf.types:func
-- @tparam string name
-- @tparam integer nparams
-- @tparam integer linkage `btf.linkage.STATIC` or `.GLOBAL`
-- @tparam table signature `{result, param}` type ids
-- @treturn integer the `FUNC` type id
function types:func(name, nparams, linkage, signature)
	local params = {}
	for i = 1, nparams do
		insert(params, pack("<I4I4", self:string("a" .. i), signature.param))
	end
	local proto = self:add(pack("<I4I4I4", 0, typeinfo(KIND_FUNC_PROTO, nparams), signature.result)
		.. concat(params))
	return self:add(pack("<I4I4I4", self:string(name), typeinfo(KIND_FUNC, linkage), proto))
end

---
-- A pointer to `id`.
-- @function luaebpf.btf.types:pointer
-- @tparam integer id
-- @treturn integer its type id
function types:pointer(id)
	return self:add(pack("<I4I4I4", 0, typeinfo(KIND_PTR, 0), id))
end

---
-- An array of `n` elements of `id`, indexed by `self.int`. libbpf reads a BTF-defined map's
-- attributes out of the element count of such an array, so `n` is the number that matters.
-- @function luaebpf.btf.types:array
-- @tparam integer id
-- @tparam integer n
-- @treturn integer its type id
function types:array(id, n)
	return self:add(pack("<I4I4I4", 0, typeinfo(KIND_ARRAY, 0), 0)
		.. pack("<I4I4I4", id, self.int, n))
end

---
-- A struct of `members`, each `{name, type}`, laid out one word apart.
-- @function luaebpf.btf.types:struct
-- @tparam string name
-- @tparam table members
-- @treturn integer the `STRUCT` type id
-- @treturn integer its size in bytes
function types:struct(name, members)
	local fields, size = {}, #members * WORD
	for i, member in ipairs(members) do
		insert(fields, pack("<I4I4I4", self:string(member.name), member.type,
			(i - 1) * WORD * BYTE))
	end
	return self:add(pack("<I4I4I4", self:string(name), typeinfo(KIND_STRUCT, #members), size)
		.. concat(fields)), size
end

---
-- A variable of `id` allocated in a section.
-- @function luaebpf.btf.types:var
-- @tparam string name
-- @tparam integer id
-- @treturn integer its type id
function types:var(name, id)
	return self:add(pack("<I4I4I4", self:string(name), typeinfo(KIND_VAR, 0), id)
		.. pack("<I4", ALLOCATED))
end

---
-- A data section holding `entries`, each `{type, offset, size}`.
-- @function luaebpf.btf.types:datasec
-- @tparam string name
-- @tparam table entries
-- @treturn integer its type id
function types:datasec(name, entries)
	local records, size = {}, 0
	for _, entry in ipairs(entries) do
		insert(records, pack("<I4I4I4", entry.type, entry.offset, entry.size))
		size = size + entry.size
	end
	return self:add(pack("<I4I4I4", self:string(name), typeinfo(KIND_DATASEC, #entries), size)
		.. concat(records))
end

---
-- The `.BTF` section.
-- @function luaebpf.btf.types:pack
-- @treturn string
function types:pack()
	local body, strings = concat(self.records), concat(self.strings)
	return pack("<I2I1I1I4I4I4I4I4", MAGIC, VERSION, 0, HDRLEN, 0, #body, #body, #strings)
		.. body .. strings
end

local function segment(self, sections, recsize, field)
	local out = {pack("<I4", recsize)}
	for _, section in ipairs(sections) do
		local records = section[field]
		if #records > 0 then
			insert(out, pack("<I4I4", self:string(section.name), #records))
			for _, record in ipairs(records) do
				insert(out, record)
			end
		end
	end
	return concat(out)
end

---
-- One `func_info` record: the byte offset of the function's first instruction, and its `FUNC`.
-- @function luaebpf.btf.funcinfo
-- @tparam integer at
-- @tparam integer id
-- @treturn string
function btf.funcinfo(at, id)
	return pack("<I4I4", at, id)
end

---
-- One `line_info` record. `line` and `column` are packed as the kernel reads them back.
-- @function luaebpf.btf.lineinfo
-- @tparam integer at byte offset of the instruction
-- @tparam integer file offset of the file name in the BTF strings
-- @tparam integer text offset of the source line in the BTF strings
-- @tparam integer line
-- @tparam integer column
-- @treturn string
function btf.lineinfo(at, file, text, line, column)
	return pack("<I4I4I4I4", at, file, text, (line << 10) | column)
end

---
-- The `.BTF.ext` section over `sections`, each `{name, funcs, lines}`.
-- @function luaebpf.btf.types:ext
-- @tparam table sections
-- @treturn string
function types:ext(sections)
	local funcs = segment(self, sections, FUNCREC, "funcs")
	local lines = segment(self, sections, LINEREC, "lines")
	return pack("<I2I1I1I4I4I4I4I4I4I4", MAGIC, VERSION, 0, EXTLEN, 0, #funcs, #funcs, #lines,
		#funcs + #lines, 0) .. funcs .. lines
end

return btf

