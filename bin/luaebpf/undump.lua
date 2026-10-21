--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Reads a binary chunk into prototype tables, field by field as `loadFunction` in `lua/lundump.c`
-- does, and rewrites one in another build's numbering.
--
-- The CLI's Lua cannot `load` a chunk `lunatic` writes: its header carries an integer
-- `lua_Number`, and its opcodes and metamethod events are numbered without the ones `_KERNEL`
-- fences out. Both are read here with the tables `make` printed from each `lua/` build,
-- `luaebpf.bytecode.kernel` for `lunatic`'s and `luaebpf.bytecode.host` for the CLI's.
-- @module luaebpf.undump

local class = require("lunatik.class")

local unpack = string.unpack
local pack   = string.pack
local char   = string.char
local format = string.format
local insert = table.insert
local concat = table.concat

local VARINT <const> = 0x7f
local MORE   <const> = 0x80

local reader = class{}

local function fail(self, why)
	error(format("%s: bad binary format (%s)", self.name, why), 0)
end

function reader:take(n)
	local at = self.at
	if at + n - 1 > #self.bytes then
		fail(self, "truncated chunk")
	end
	self.at = at + n
	return self.bytes:sub(at, at + n - 1)
end

function reader:byte()
	return (self:take(1):byte())
end

function reader:unpack(spec, size)
	return (unpack("=" .. spec, self:take(size)))
end

function reader:signed(size)
	return self:unpack("i" .. size, size)
end

function reader:unsigned(size)
	return self:unpack("I" .. size, size)
end

function reader:varint()
	local x, b = 0, nil
	repeat
		b = self:byte()
		x = (x << 7) | (b & VARINT)
	until b & MORE == 0
	return x
end

-- loadInteger: the sign in the lowest bit
function reader:integer()
	local cx = self:varint()
	return cx & 1 ~= 0 and ~(cx >> 1) or cx >> 1
end

-- loadAlign counts the chunk's first byte as read
function reader:align(n)
	local padding = n - ((self.at - 1) % n)
	if padding < n then
		self:take(padding)
	end
end

-- a string the chunk wrote before is written again as its index among the ones saved
function reader:string()
	local size = self:varint()
	if size == 0 then
		local index = self:varint()
		if index == 0 then
			return nil
		end
		return self.saved[index] or fail(self, "invalid string index")
	end
	local s = self:take(size):sub(1, size - 1)
	insert(self.saved, s)
	return s
end

function reader:number()
	local fmt = self.format
	if fmt.FLOAT then
		return self:unpack("n", fmt.NUMBER)
	end
	return self:signed(fmt.NUMBER)
end

local function field(i, pos, size)
	return (i >> pos) & ((1 << size) - 1)
end

local decoders = {}

function decoders.iABC(layout, i, ins)
	ins.a = field(i, layout.POS_A, layout.SIZE_A)
	ins.b = field(i, layout.POS_B, layout.SIZE_B)
	ins.c = field(i, layout.POS_C, layout.SIZE_C)
	ins.sb = ins.b - layout.OFFSET_sC
	ins.sc = ins.c - layout.OFFSET_sC
	ins.k = field(i, layout.POS_k, 1) ~= 0
end

function decoders.ivABC(layout, i, ins)
	ins.a = field(i, layout.POS_A, layout.SIZE_A)
	ins.vb = field(i, layout.POS_vB, layout.SIZE_vB)
	ins.vc = field(i, layout.POS_vC, layout.SIZE_vC)
	ins.k = field(i, layout.POS_k, 1) ~= 0
end

function decoders.iABx(layout, i, ins)
	ins.a = field(i, layout.POS_A, layout.SIZE_A)
	ins.bx = field(i, layout.POS_Bx, layout.SIZE_Bx)
end

function decoders.iAsBx(layout, i, ins)
	ins.a = field(i, layout.POS_A, layout.SIZE_A)
	ins.sbx = field(i, layout.POS_Bx, layout.SIZE_Bx) - layout.OFFSET_sBx
end

function decoders.iAx(layout, i, ins)
	ins.ax = field(i, layout.POS_Ax, layout.SIZE_Ax)
end

function decoders.isJ(layout, i, ins)
	ins.sj = field(i, layout.POS_sJ, layout.SIZE_sJ) - layout.OFFSET_sJ
	ins.k = field(i, layout.POS_k, 1) ~= 0
end

function reader:instruction()
	local layout = self.layout
	local i = self:unsigned(self.format.INSTRUCTION)
	local ins = {op = field(i, layout.POS_OP, layout.SIZE_OP)}
	local decode = self.decoders[ins.op]
	if decode == nil then
		fail(self, "invalid opcode")
	end
	decode(layout, i, ins)
	return ins
end

-- by the variant tag each is dumped under, which the format table numbers
local constants = {}

function constants.LUA_VNIL()
	return nil
end

function constants.LUA_VFALSE()
	return false
end

function constants.LUA_VTRUE()
	return true
end

function constants.LUA_VNUMINT(self)
	return self:integer()
end

function constants.LUA_VNUMFLT(self)
	return self:number()
end

function constants.LUA_VSHRSTR(self)
	return self:string() or fail(self, "bad format for constant string")
end

constants.LUA_VLNGSTR = constants.LUA_VSHRSTR

function reader:constant()
	local read = self.constants[self:byte()]
	if read == nil then
		fail(self, "invalid constant")
	end
	return read(self)
end

-- luaG_getfuncline, over the whole function at once
local function funclines(p, lineinfo, abslineinfo)
	local lines = {}
	if #lineinfo == 0 then
		return lines
	end
	local line, abs = p.linedefined, 1
	for pc = 0, #p.code - 1 do
		local base = abslineinfo[abs]
		if base ~= nil and base.pc == pc then
			line, abs = base.line, abs + 1
		else
			line = line + lineinfo[pc + 1]
		end
		lines[pc + 1] = line
	end
	return lines
end

function reader:debug(p)
	local fmt = self.format
	local lineinfo, abslineinfo = {}, {}
	for i = 1, self:varint() do
		lineinfo[i] = self:signed(1)
	end
	local nabs = self:varint()
	if nabs > 0 then
		self:align(fmt.INT)
		for i = 1, nabs do
			abslineinfo[i] = {pc = self:signed(fmt.INT), line = self:signed(fmt.INT)}
		end
	end
	for _ = 1, self:varint() do -- the local variables, which the translator does not read
		self:string()
		self:varint()
		self:varint()
	end
	if self:varint() ~= 0 then
		for _, upvalue in ipairs(p.upvalues) do
			upvalue.name = self:string()
		end
	end
	p.lines = funclines(p, lineinfo, abslineinfo)
end

function reader:load()
	local fmt = self.format
	local p = {code = {}, k = {}, upvalues = {}, protos = {}}
	p.linedefined = self:varint()
	p.lastlinedefined = self:varint()
	p.numparams = self:byte()
	p.isvararg = self:byte() & (fmt.PF_VAHID | fmt.PF_VATAB) ~= 0
	p.maxstacksize = self:byte()
	local ncode = self:varint()
	self:align(fmt.INSTRUCTION)
	p.at = self.at -- where its code starts, which the rewrite renumbers in place
	for pc = 1, ncode do
		p.code[pc] = self:instruction()
	end
	p.nk = self:varint() -- k holds nil constants, so # cannot count them
	for i = 1, p.nk do
		p.k[i] = self:constant()
	end
	for i = 1, self:varint() do
		p.upvalues[i] = {instack = self:byte() ~= 0, idx = self:byte()}
		self:byte() -- the variable's kind
	end
	for i = 1, self:varint() do
		p.protos[i] = self:load()
	end
	p.source = self:string()
	self:debug(p)
	return p
end

function reader:literal(s, why)
	if self:take(#s) ~= s then
		fail(self, why)
	end
end

function reader:checknum(what, size, read, value)
	if self:byte() ~= size then
		fail(self, what .. " size mismatch")
	end
	if read(self, size) ~= value then
		fail(self, what .. " format mismatch")
	end
end

function reader:header()
	local fmt = self.format
	self:literal(fmt.SIGNATURE, "not a binary chunk")
	if self:byte() ~= fmt.LUAC_VERSION then
		fail(self, "version mismatch")
	end
	if self:byte() ~= fmt.LUAC_FORMAT then
		fail(self, "format mismatch")
	end
	self:literal(fmt.DATA, "corrupted chunk")
	self:checknum("int", fmt.INT, reader.signed, fmt.LUAC_INT)
	self:checknum("instruction", fmt.INSTRUCTION, reader.unsigned, fmt.LUAC_INST)
	self:checknum("Lua integer", fmt.INTEGER, reader.signed, fmt.LUAC_INT)
	self:checknum("Lua number", fmt.NUMBER, reader.number, fmt.LUAC_NUM)
end

local undump = {}

local function open(bytes, name, tables)
	local fmt = tables.format
	local self = reader:new{bytes = bytes, at = 1, name = name, saved = {}, format = fmt,
		layout = tables.layout, decoders = {}, constants = {}}
	for _, opcode in pairs(tables.opcodes) do
		self.decoders[opcode.op] = decoders[opcode.mode]
	end
	for tag, read in pairs(constants) do
		if fmt[tag] ~= nil then -- the kernel's Lua has no float tag
			self.constants[fmt[tag]] = read
		end
	end
	return self
end

---
-- Reads the chunk in `bytes`.
-- @function luaebpf.undump.read
-- @tparam string bytes the chunk
-- @tparam string name what an error calls it
-- @tparam table tables the `luaebpf.bytecode` tables of the build that wrote it
-- @treturn table the main function's prototype, `{source, linedefined, lastlinedefined,
--   numparams, isvararg, maxstacksize, nk, code, lines, k, upvalues, protos}`, its nested
--   functions in `protos`
-- @raise `<name>: bad binary format (<reason>)`, as `lua/lundump.c` words it
function undump.read(bytes, name, tables)
	local self = open(bytes, name, tables)
	self:header()
	self:byte() -- the main closure's upvalue count, which its prototype carries too
	return self:load()
end

local function header(fmt)
	return fmt.SIGNATURE .. char(fmt.LUAC_VERSION, fmt.LUAC_FORMAT) .. fmt.DATA ..
		pack("=Bi" .. fmt.INT, fmt.INT, fmt.LUAC_INT) ..
		pack("=BI" .. fmt.INSTRUCTION, fmt.INSTRUCTION, fmt.LUAC_INST) ..
		pack("=Bi" .. fmt.INTEGER, fmt.INTEGER, fmt.LUAC_INT) ..
		pack("=Bn", fmt.NUMBER, fmt.LUAC_NUM)
end

local function setfield(i, pos, size, value)
	local mask = ((1 << size) - 1) << pos
	return (i & ~mask) | (value << pos)
end

-- the instructions that carry a metamethod event in C, for the VM to call when the fast path fails
local carriesevent = {MMBIN = true, MMBINI = true, MMBINK = true}

local function renumber(rewrite, p, pieces)
	local to, layout = rewrite.to, rewrite.to.layout
	local spec = "=I" .. rewrite.from.format.INSTRUCTION
	insert(pieces, rewrite.bytes:sub(rewrite.at, p.at - 1))
	for pc, ins in ipairs(p.code) do
		local name = rewrite.opnames[ins.op]
		local i = setfield(unpack(spec, rewrite.bytes, p.at + (pc - 1) * rewrite.size), layout.POS_OP,
			layout.SIZE_OP, to.opcodes[name].op)
		if carriesevent[name] then
			i = setfield(i, layout.POS_C, layout.SIZE_C, to.events[rewrite.events[ins.c]])
		end
		insert(pieces, pack(spec, i))
	end
	rewrite.at = p.at + #p.code * rewrite.size
	for _, nested in ipairs(p.protos) do
		renumber(rewrite, nested, pieces)
	end
end

---
-- Rewrites the chunk in `bytes`, which the build `from` wrote, as the build `to` writes it: the
-- header, and each opcode and metamethod event by name. Every opcode and event of the kernel's Lua
-- is one of the CLI's, and the two headers are one size, so nothing else moves.
-- @function luaebpf.undump.rewrite
-- @tparam string bytes the chunk
-- @tparam string name what an error calls it
-- @tparam table from the `luaebpf.bytecode` tables of the build that wrote it
-- @tparam table to the tables of the build that is to load it, whose numbers are floats as the CLI's are
-- @treturn string the chunk `to` loads
-- @raise `<name>: bad binary format (<reason>)`, as `luaebpf.undump.read` does
function undump.rewrite(bytes, name, from, to)
	local self = open(bytes, name, from)
	self:header()
	local head = header(to.format)
	if #head ~= self.at - 1 then
		fail(self, "header size mismatch")
	end
	local rewrite = {bytes = bytes, at = self.at, from = from, to = to, opnames = {}, events = {},
		size = from.format.INSTRUCTION}
	for name, opcode in pairs(from.opcodes) do
		rewrite.opnames[opcode.op] = name
	end
	for event, number in pairs(from.events) do
		rewrite.events[number] = event
	end
	self:byte()
	local pieces = {head}
	renumber(rewrite, self:load(), pieces)
	insert(pieces, bytes:sub(rewrite.at))
	return concat(pieces)
end

return undump

