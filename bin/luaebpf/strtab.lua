--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A string table as ELF and BTF both lay one out: each string once, NUL-terminated, after the
-- empty string at offset 0.
-- @module luaebpf.strtab

local class = require("lunatik.class")

local insert = table.insert
local concat = table.concat

local strtab = {}

---
-- A string table under construction.
-- @type luaebpf.strtab.strings
local strings = class{}

---
-- A table holding the empty string alone.
-- @function luaebpf.strtab.new
-- @treturn luaebpf.strtab.strings
function strtab.new()
	return strings:new{list = {"\0"}, offsets = {[""] = 0}, length = 1}
end

---
-- Interns a string.
-- @function luaebpf.strtab.strings:intern
-- @tparam string name
-- @treturn integer its offset in the table
function strings:intern(name)
	local at = self.offsets[name]
	if at ~= nil then
		return at
	end
	at = self.length
	insert(self.list, name .. "\0")
	self.offsets[name] = at
	self.length = at + #name + 1
	return at
end

---
-- The table as bytes.
-- @function luaebpf.strtab.strings:pack
-- @treturn string
function strings:pack()
	return concat(self.list)
end

return strtab

