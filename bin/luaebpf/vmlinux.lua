--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The running kernel's own type information, read from `/sys/kernel/btf/vmlinux`.
--
-- A layout comes back in the shape `autogen` emits and `struct` consumes, so a kernel struct
-- becomes a codec, a map value spec or a set of context offsets with nothing transcribed from a
-- header. BTF records no member's byte offset directly: the file is a flat stream of
-- variable-length records naming each other by type id, so one pass records where every id
-- starts and a struct's members resolve in constant time afterwards.
-- @module luaebpf.vmlinux
-- @usage
-- local vmlinux = require("luaebpf.vmlinux")
-- local struct  = require("struct")
--
-- local skb = struct(vmlinux.layout("__sk_buff"))

local unpack = string.unpack
local insert = table.insert

local VMLINUX  <const> = "/sys/kernel/btf/vmlinux"
local MAGIC    <const> = 0xeb9f
local HDRLEN   <const> = 24
local TYPESIZE <const> = 12
local MEMBER   <const> = 12
local BYTE     <const> = 8
local NESTING  <const> = 16 -- qualifiers a member's type may be wrapped in, so a cycle ends

-- uapi/linux/btf.h, BTF_KIND_*
local INT        <const> = 1
local ARRAY      <const> = 3
local STRUCT     <const> = 4
local UNION      <const> = 5
local ENUM       <const> = 6
local TYPEDEF    <const> = 8
local VOLATILE   <const> = 9
local CONST      <const> = 10
local RESTRICT   <const> = 11
local FUNC_PROTO <const> = 13
local VAR        <const> = 14
local DATASEC    <const> = 15
local DECL_TAG   <const> = 17
local TYPE_TAG   <const> = 18
local ENUM64     <const> = 19

local SIGNED <const> = 1 -- BTF_INT_SIGNED

-- what follows a btf_type record: a fixed tail, and one record per member the vlen counts
local tails   = {[INT] = 4, [ARRAY] = 12, [VAR] = 4, [DECL_TAG] = 4}
local records = {[STRUCT] = MEMBER, [UNION] = MEMBER, [ENUM] = 8, [ENUM64] = 12,
	[FUNC_PROTO] = 8, [DATASEC] = 12}

-- a member's type is read through the qualifiers a C declaration may wrap it in
local qualifiers = {[TYPEDEF] = true, [VOLATILE] = true, [CONST] = true, [RESTRICT] = true,
	[TYPE_TAG] = true}

-- an enum is an integer of its own size, whose kind_flag says whether its values are signed;
-- only an INT says where its bits sit in their word
local integers = {[INT] = true, [ENUM] = true, [ENUM64] = true}

local vmlinux = {}

-- one scan of a five-megabyte file answers every struct a compilation asks for
local cached

local function read(path)
	local file = io.open(path, "rb")
	if file == nil then
		return nil
	end
	local bytes = file:read("a")
	file:close()
	return bytes
end

local function name(self, at)
	return (unpack("z", self.bytes, self.strings + at))
end

-- one pass over the type section: where each id starts, and the id of each named struct
local function index(bytes)
	local magic, _, _, hdrlen, typeoff, typelen, stroff = unpack("<I2I1I1I4I4I4I4", bytes)
	if magic ~= MAGIC or hdrlen < HDRLEN then
		return nil
	end
	local self = {bytes = bytes, strings = hdrlen + stroff + 1, offsets = {}, structs = {}}
	local at, last, id = hdrlen + typeoff + 1, hdrlen + typeoff + typelen, 0
	while at <= last do
		local nameoff, info = unpack("<I4I4", bytes, at)
		local kind, vlen = (info >> 24) & 0x1f, info & 0xffff
		id = id + 1
		self.offsets[id] = at
		if kind == STRUCT then
			self.structs[name(self, nameoff)] = id
		end
		at = at + TYPESIZE + (tails[kind] or 0) + (records[kind] or 0) * vlen
	end
	return self
end

-- the type a member names, with every typedef and qualifier stripped
local function resolve(self, id)
	for _ = 1, NESTING do
		local at = self.offsets[id]
		if at == nil then
			return nil
		end
		local _, info, size = unpack("<I4I4I4", self.bytes, at)
		local kind = (info >> 24) & 0x1f
		if not qualifiers[kind] then
			return kind, size, at
		end
		id = size
	end
	return nil
end

-- an INT says how many bits it takes and where in its word they sit, so a bitfield declared
-- without a kind_flag is caught here rather than by its member's offset
local function scalar(self, id)
	local kind, size, at = resolve(self, id)
	if kind == nil or not integers[kind] then
		return nil
	end
	if kind ~= INT then
		local _, info = unpack("<I4I4", self.bytes, at)
		return size, info >> 31 == 1
	end
	local encoding = unpack("<I4", self.bytes, at + TYPESIZE)
	local bits, offset = encoding & 0xff, (encoding >> 16) & 0xff
	if offset ~= 0 or bits ~= size * BYTE then
		return nil
	end
	return size, (encoding >> 24) & SIGNED ~= 0
end

local function members(self, at, vlen, kflag)
	local fields = {}
	for i = 0, vlen - 1 do
		local nameoff, typeid, offset = unpack("<I4I4I4", self.bytes, at + TYPESIZE + i * MEMBER)
		local bitfield = kflag == 1 and offset >> 24 or 0
		local bit = kflag == 1 and offset & 0xffffff or offset
		local size, signed = scalar(self, typeid)
		if size ~= nil and bitfield == 0 and bit % BYTE == 0 then
			insert(fields, {name = name(self, nameoff), offset = bit // BYTE,
				size = size, signed = signed})
		end
	end
	return fields
end

local function reader()
	if cached == nil then
		local bytes = read(VMLINUX)
		cached = bytes ~= nil and index(bytes) or false
	end
	return cached or nil
end

---
-- The layout of a kernel struct.
--
-- A member is reported when its type resolves to an integer of a whole number of bytes at a
-- byte-aligned offset; a bitfield, a union such as `__sk_buff`'s `__bpf_md_ptr` members, and a
-- nested struct are absent, and `struct` reads the gap they leave as padding.
-- @function luaebpf.vmlinux.layout
-- @tparam string what the struct's name, as `bpftool btf dump` prints it
-- @treturn table `{size = bytes, fields = {{name, offset, size, signed}, ...}}`, offsets and
--   sizes in bytes
-- @raise `the kernel publishes no BTF`, when `/sys/kernel/btf/vmlinux` cannot be read or carries
--   no BTF header, and `the kernel BTF has no struct '<what>'`
function vmlinux.layout(what)
	local self = reader()
	if self == nil then
		error("the kernel publishes no BTF", 0)
	end
	local id = self.structs[what]
	if id == nil then
		error(("the kernel BTF has no struct '%s'"):format(what), 0)
	end
	local at = self.offsets[id]
	local _, info, size = unpack("<I4I4I4", self.bytes, at)
	return {size = size, fields = members(self, at, info & 0xffff, info >> 31)}
end

return vmlinux

