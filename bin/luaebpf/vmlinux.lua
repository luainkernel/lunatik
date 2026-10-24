--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The kernel's own type information, read from a raw BTF file: `/sys/kernel/btf/vmlinux`, the
-- running kernel's, unless `luaebpf.compile` is handed the BTF of the kernel it compiles for.
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
local SWAPPED  <const> = 0x9feb -- the magic read in the other byte order, as libbpf's btf_parse_hdr tells it
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

-- the byte order a refusal names for each prefix string.unpack reads a BTF with
local endianness = {["<"] = "little", [">"] = "big"}

local vmlinux = {}

-- the file the layouts are read from, and one scan of it, which answers every struct a
-- compilation asks for
local source, cached = VMLINUX, nil

local function name(self, at)
	return (unpack("z", self.bytes, self.strings + at))
end

-- the prefix string.unpack reads a BTF with, which its magic says
local function order(bytes)
	if #bytes < HDRLEN then
		return nil
	end
	local magic = unpack("<I2", bytes)
	return magic == MAGIC and "<" or magic == SWAPPED and ">" or nil
end

-- one pass over the type section: where each id starts, and the id of each named struct; or nil and
-- what the bytes are not
local function index(bytes)
	local endian = order(bytes)
	if endian == nil then
		return nil, "carries no BTF header"
	end
	local _, _, _, hdrlen, typeoff, typelen, stroff, strlen = unpack(endian .. "I2I1I1I4I4I4I4I4", bytes)
	if hdrlen < HDRLEN then
		return nil, "carries no BTF header"
	end
	-- the bounds btf_parse_hdr checks, so a file cut short is refused rather than read past its end
	if typeoff + typelen > stroff or hdrlen + stroff + strlen > #bytes then
		return nil, "is shorter than its BTF header says"
	end
	local self = {bytes = bytes, order = endian, strings = hdrlen + stroff + 1, offsets = {}, structs = {}}
	local at, last, id = hdrlen + typeoff + 1, hdrlen + typeoff + typelen, 0
	while at <= last do
		local nameoff, info = unpack(endian .. "I4I4", bytes, at)
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
		local _, info, size = unpack(self.order .. "I4I4I4", self.bytes, at)
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
		local _, info = unpack(self.order .. "I4I4", self.bytes, at)
		return size, info >> 31 == 1
	end
	local encoding = unpack(self.order .. "I4", self.bytes, at + TYPESIZE)
	local bits, offset = encoding & 0xff, (encoding >> 16) & 0xff
	if offset ~= 0 or bits ~= size * BYTE then
		return nil
	end
	return size, (encoding >> 24) & SIGNED ~= 0
end

local function members(self, at, vlen, kflag)
	local fields = {}
	for i = 0, vlen - 1 do
		local nameoff, typeid, offset = unpack(self.order .. "I4I4I4", self.bytes, at + TYPESIZE + i * MEMBER)
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
		local file, err = io.open(source, "rb")
		if file == nil then
			error(err, 0)
		end
		local bytes = file:read("a")
		file:close()
		local reason
		cached, reason = index(bytes or "")
		if cached == nil then
			error(("%s %s"):format(source, reason), 0)
		end
	end
	return cached
end

---
-- Reads the layouts from the raw BTF file at `path` from then on, the bytes
-- `/sys/kernel/btf/vmlinux` serves, in the byte order its magic is written in. The file is read
-- when a layout is first asked for.
-- @function luaebpf.vmlinux.open
-- @tparam[opt] string path the file, `/sys/kernel/btf/vmlinux` when absent
function vmlinux.open(path)
	path = path or VMLINUX
	if path ~= source then
		source, cached = path, nil
	end
end

---
-- Refuses the BTF a layout was read from when it is not in the object's byte order, since it then
-- describes another kernel than the one the object is for.
-- @function luaebpf.vmlinux.check
-- @tparam boolean bigendian whether the object is big-endian
-- @raise `<path> is a <order>-endian BTF, for a <order>-endian object`
function vmlinux.check(bigendian)
	local expected = bigendian and ">" or "<"
	if cached ~= nil and cached.order ~= expected then
		error(("%s is a %s-endian BTF, for a %s-endian object"):format(source, endianness[cached.order],
			endianness[expected]), 0)
	end
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
-- @raise `<path>: <reason>`, when the BTF file cannot be read, `<path> carries no BTF header`,
--   `<path> is shorter than its BTF header says`, and `the kernel BTF has no struct '<what>'`
function vmlinux.layout(what)
	local self = reader()
	local id = self.structs[what]
	if id == nil then
		error(("the kernel BTF has no struct '%s'"):format(what), 0)
	end
	local at = self.offsets[id]
	local _, info, size = unpack(self.order .. "I4I4I4", self.bytes, at)
	return {size = size, fields = members(self, at, info & 0xffff, info >> 31)}
end

return vmlinux

