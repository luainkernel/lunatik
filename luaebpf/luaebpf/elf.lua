--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The relocatable ELF object libbpf loads: sections, a symbol table and the call relocations.
--
-- One string table serves both the section names and the symbol names. A symbol table lists its
-- local symbols first and says in `sh_info` where the global ones begin, so `symbol` refuses a
-- local added after a global rather than renumbering what a relocation already names.
-- @module luaebpf.elf

local class = require("class")

local pack   = string.pack
local concat = table.concat
local insert = table.insert

local EHSIZE      <const> = 64
local SHENTSIZE   <const> = 64
local SYMSIZE     <const> = 24
local RELSIZE     <const> = 16
local EM_BPF      <const> = 247
local ET_REL      <const> = 1

local elf = {}

--- Section types, as `SHT_*` names them.
-- @table luaebpf.elf.section
elf.section = {PROGBITS = 1, SYMTAB = 2, STRTAB = 3, REL = 9}

--- Section flags, as `SHF_*` names them.
-- @table luaebpf.elf.flags
elf.flags = {WRITE = 0x1, ALLOC = 0x2, EXEC = 0x4}

--- Symbol bindings, as `STB_*` names them.
-- @table luaebpf.elf.bind
elf.bind = {LOCAL = 0, GLOBAL = 1}

--- Symbol types, as `STT_*` names them.
-- @table luaebpf.elf.type
elf.type = {NOTYPE = 0, OBJECT = 1, FUNC = 2}

--- The section an undefined symbol names, which is the null section at index 0.
-- @field luaebpf.elf.UNDEF
elf.UNDEF = ""

--- Relocation types: `IMM64` is `R_BPF_64_64`, which patches the immediate of an `ld_imm64`,
-- and `IMM32` is `R_BPF_64_32`, which patches a 32-bit one.
-- @table luaebpf.elf.relocation
elf.relocation = {IMM64 = 1, IMM32 = 10}

---
-- An object under construction.
-- @type luaebpf.elf.object
local object = class{}

---
-- A fresh object, with its null section and null symbol already in place.
-- @function luaebpf.elf.new
-- @treturn luaebpf.elf.object
function elf.new()
	return object:new{sections = {{name = "", data = ""}}, indexes = {[elf.UNDEF] = 0}, nlocals = 1,
		symbols = {pack("<I4I1I1I2I8I8", 0, 0, 0, 0, 0, 0)}, strings = {"\0"},
		offsets = {[""] = 0}, length = 1}
end

---
-- Interns a string in the object's string table.
-- @function luaebpf.elf.object:string
-- @tparam string name
-- @treturn integer its offset in the table
function object:string(name)
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
-- Appends a section.
-- @function luaebpf.elf.object:section
-- @tparam table section `{name, type, flags, data, link, info, align, entsize}`; `link` and a
--   string `info` name another section.
-- @treturn integer the section's index
function object:section(section)
	self:string(section.name)
	insert(self.sections, section)
	self.indexes[section.name] = #self.sections - 1
	return #self.sections - 1
end

---
-- Appends a symbol.
-- @function luaebpf.elf.object:symbol
-- @tparam table symbol `{name, section, value, size, bind, type}`, `type` one of `elf.type`
-- @treturn integer the symbol's index
-- @raise a local symbol follows a global one
function object:symbol(symbol)
	if symbol.bind == elf.bind.LOCAL then
		if #self.symbols > self.nlocals then
			error("luaebpf.elf: a local symbol follows a global one", 0)
		end
		self.nlocals = self.nlocals + 1
	end
	insert(self.symbols, pack("<I4I1I1I2I8I8", self:string(symbol.name),
		(symbol.bind << 4) | symbol.type, 0, self.indexes[symbol.section], symbol.value,
		symbol.size))
	return #self.symbols - 1
end

---
-- A relocation section for `name`, each entry `{at, symbol, type}` with `at` a byte offset into
-- the relocated section and `type` one of `elf.relocation`.
-- @function luaebpf.elf.object:relocations
-- @tparam string name the relocated section
-- @tparam table entries
function object:relocations(name, entries)
	local records = {}
	for _, entry in ipairs(entries) do
		insert(records, pack("<I8I8", entry.at, (entry.symbol << 32) | entry.type))
	end
	self:section{name = ".rel" .. name, type = elf.section.REL, flags = 0, data = concat(records),
		link = ".symtab", info = name, align = 8, entsize = RELSIZE}
end

local function place(self)
	local offset = EHSIZE
	for i = 2, #self.sections do
		local section = self.sections[i]
		local align = section.align or 1
		offset = offset + (align - offset % align) % align
		section.offset = offset
		offset = offset + #section.data
	end
	return offset
end

local function headers(self)
	local out = {pack("<I4I4I8I8I8I8I4I4I8I8", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)}
	for i = 2, #self.sections do
		local section = self.sections[i]
		local link = section.link ~= nil and self.indexes[section.link] or 0
		local info = type(section.info) == "string" and self.indexes[section.info] or (section.info or 0)
		insert(out, pack("<I4I4I8I8I8I8I4I4I8I8", self.offsets[section.name], section.type,
			section.flags, 0, section.offset, #section.data, link, info,
			section.align or 1, section.entsize or 0))
	end
	return concat(out)
end

---
-- The object as bytes. The symbol and string tables are written here, last, so that every name
-- they carry is already interned.
-- @function luaebpf.elf.object:pack
-- @treturn string
function object:pack()
	self:section{name = ".symtab", type = elf.section.SYMTAB, flags = 0, data = concat(self.symbols),
		link = ".strtab", info = self.nlocals, align = 8, entsize = SYMSIZE}
	local strtab = self:section{name = ".strtab", type = elf.section.STRTAB, flags = 0, align = 1}
	self.sections[strtab + 1].data = concat(self.strings)

	local shoff = place(self)
	shoff = shoff + (8 - shoff % 8) % 8
	local out = {pack("<I4I1I1I1I1I1", 0x464c457f, 2, 1, 1, 0, 0), ("\0"):rep(7),
		pack("<I2I2I4I8I8I8I4I2I2I2I2I2I2", ET_REL, EM_BPF, 1, 0, 0, shoff, 0,
			EHSIZE, 0, 0, SHENTSIZE, #self.sections, strtab)}
	local at = EHSIZE
	for i = 2, #self.sections do
		local section = self.sections[i]
		insert(out, ("\0"):rep(section.offset - at))
		insert(out, section.data)
		at = section.offset + #section.data
	end
	insert(out, ("\0"):rep(shoff - at))
	insert(out, headers(self))
	return concat(out)
end

return elf

