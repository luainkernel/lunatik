--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- eBPF instructions, and the buffer the translator emits them into.
--
-- A buffer holds records rather than bytes, so a jump can name a label placed later and a call
-- can name a function laid out afterwards; `pack` resolves both against the positions the
-- assembler hands it. Every record carries the Lua line it came from, which is what the
-- `line_info` writer reads.
-- @module luaebpf.insn

local class = require("class")

local pack   = string.pack
local concat = table.concat
local insert = table.insert

-- instruction classes and fields: uapi/linux/bpf.h, uapi/linux/bpf_common.h
local LD    <const> = 0x00
local LDX   <const> = 0x01
local ST    <const> = 0x02
local STX   <const> = 0x03
local JMP   <const> = 0x05
local ALU64 <const> = 0x07
local W     <const> = 0x00
local H     <const> = 0x08
local B     <const> = 0x10
local DW    <const> = 0x18
local MEM   <const> = 0x60
local SRC_X <const> = 0x08
local PSEUDO_CALL <const> = 1
local MAY_GOTO    <const> = 0
local SIZE  <const> = 8
local WORD  <const> = 8

-- the field an access of that many bytes carries, BPF_B and friends
local widths = {[1] = B, [2] = H, [4] = W, [8] = DW}

-- string.pack's i4 takes a signed word; the halves of a 64-bit immediate are unsigned
local function word(value)
	value = value & 0xffffffff
	if value >= 0x80000000 then
		return value - 0x100000000
	end
	return value
end

local insn = {}

--- ALU opcodes, `BPF_ADD` and friends.
-- @table luaebpf.insn.alu
insn.alu = {
	ADD = 0x00, SUB = 0x10, MUL = 0x20, DIV = 0x30, OR = 0x40, AND = 0x50,
	LSH = 0x60, RSH = 0x70, NEG = 0x80, MOD = 0x90, XOR = 0xa0, MOV = 0xb0, ARSH = 0xc0,
}

--- Jump opcodes, `BPF_JEQ` and friends. Lua integers are signed, so a comparison the source
-- wrote takes a signed relation. The unsigned ones are for the bounds check before a packet
-- load, where the verifier reads the relation itself: a packet pointer and an offset are
-- unsigned there, and a signed test would leave the pointer's range unproven.
-- @table luaebpf.insn.jump
insn.jump = {
	JA = 0x00, JEQ = 0x10, JGT = 0x20, JGE = 0x30, JNE = 0x50, JSGT = 0x60, JSGE = 0x70,
	JLT = 0xa0, JLE = 0xb0, JSLT = 0xc0, JSLE = 0xd0, JCOND = 0xe0, CALL = 0x80, EXIT = 0x90,
}

--- Registers: `R0` to `R10`, with `FP` as the read-only frame pointer.
-- @table luaebpf.insn.reg
insn.reg = {R0 = 0, R1 = 1, R2 = 2, R3 = 3, R4 = 4, R5 = 5, R6 = 6, R7 = 7, R8 = 8, R9 = 9, FP = 10}

--- Bytes one instruction takes in the object.
-- @field luaebpf.insn.SIZE
insn.SIZE = SIZE

---
-- A code buffer.
-- @type luaebpf.insn.code
local code = class{}

local function append(self, record)
	self.n = self.n + 1
	record.line = self.line
	self.records[self.n] = record
	return self.n
end

---
-- A fresh, empty code buffer.
-- @function luaebpf.insn.new
-- @treturn luaebpf.insn.code
function insn.new()
	return code:new{n = 0, records = {}, labels = {}, nlabels = 0, line = 0}
end

---
-- The Lua source line the instructions emitted from now on come from.
-- @function luaebpf.insn.code:source
-- @tparam integer line
function code:source(line)
	self.line = line
end

---
-- A label, to be placed with `place` and named by a jump.
-- @function luaebpf.insn.code:label
-- @treturn integer the label
function code:label()
	self.nlabels = self.nlabels + 1
	return self.nlabels
end

---
-- Binds `label` to the position the next instruction takes.
-- @function luaebpf.insn.code:place
-- @tparam integer label
function code:place(label)
	self.labels[label] = self.n
end

--- `dst := dst op src`, on 64 bits.
-- @function luaebpf.insn.code:alu
function code:alu(op, dst, src)
	return append(self, {code = ALU64 | op | SRC_X, dst = dst, src = src, off = 0, imm = 0})
end

--- `dst := dst op imm`, on 64 bits; `imm` must fit in 32 signed bits.
-- @function luaebpf.insn.code:alui
function code:alui(op, dst, imm)
	return append(self, {code = ALU64 | op, dst = dst, src = 0, off = 0, imm = imm})
end

--- `dst := -dst`; eBPF's negation is a one-operand ALU op, so it takes no source.
-- @function luaebpf.insn.code:neg
function code:neg(dst)
	return self:alui(insn.alu.NEG, dst, 0)
end

--- Signed division or modulo, which eBPF spells as the unsigned op with `off` set to 1.
-- @function luaebpf.insn.code:sdiv
function code:sdiv(op, dst, src)
	return append(self, {code = ALU64 | op | SRC_X, dst = dst, src = src, off = 1, imm = 0})
end

--- `dst := imm`, over the whole 64-bit range.
-- @function luaebpf.insn.code:set
function code:set(dst, imm)
	if imm >= -0x80000000 and imm <= 0x7fffffff then
		return self:alui(insn.alu.MOV, dst, imm)
	end
	local at = append(self, {code = LD | DW, dst = dst, src = 0, off = 0, imm = word(imm)})
	append(self, {code = 0, dst = 0, src = 0, off = 0, imm = word(imm >> 32)})
	return at
end

--- `dst := *(u<8n> *)(src + off)`, zero-extended; `n` is eight bytes by default.
-- @function luaebpf.insn.code:load
function code:load(dst, src, off, n)
	return append(self, {code = LDX | widths[n or WORD] | MEM, dst = dst, src = src, off = off, imm = 0})
end

--- `*(u<8n> *)(dst + off) := src`; `n` is eight bytes by default.
-- @function luaebpf.insn.code:store
function code:store(dst, off, src, n)
	return append(self, {code = STX | widths[n or WORD] | MEM, dst = dst, src = src, off = off, imm = 0})
end

--- `*(u64 *)(dst + off) := imm`; `imm` must fit in 32 signed bits.
-- @function luaebpf.insn.code:storei
function code:storei(dst, off, imm)
	return append(self, {code = ST | DW | MEM, dst = dst, src = 0, off = off, imm = imm})
end

--- Jumps to `label` when `dst op src` holds.
-- @function luaebpf.insn.code:branch
function code:branch(op, dst, src, label)
	return append(self, {code = JMP | op | SRC_X, dst = dst, src = src, imm = 0, target = label})
end

--- Jumps to `label` when `dst op imm` holds.
-- @function luaebpf.insn.code:branchi
function code:branchi(op, dst, imm, label)
	return append(self, {code = JMP | op, dst = dst, src = 0, imm = imm, target = label})
end

--- An unconditional jump to `label`.
-- @function luaebpf.insn.code:jump
function code:jump(label)
	return append(self, {code = JMP | insn.jump.JA, dst = 0, src = 0, imm = 0, target = label})
end

--- The `may_goto` header that buys a loop the verifier cannot bound its iteration budget.
-- @function luaebpf.insn.code:maygoto
function code:maygoto(label)
	return append(self, {code = JMP | insn.jump.JCOND, dst = 0, src = MAY_GOTO, imm = 0, target = label})
end

--- A BPF-to-BPF call to the function registered under `name`.
-- @function luaebpf.insn.code:call
function code:call(name)
	return append(self, {code = JMP | insn.jump.CALL, dst = 0, src = PSEUDO_CALL, off = 0, imm = -1, call = name})
end

--- A call to the kernel helper of that number.
-- @function luaebpf.insn.code:helper
function code:helper(number)
	return append(self, {code = JMP | insn.jump.CALL, dst = 0, src = 0, off = 0, imm = number})
end

--- A call to the kfunc registered under `name`. The object carries a relocation against the
-- kfunc's undefined symbol, and libbpf writes the source register, the immediate and the offset
-- itself, from the module BTF it resolved the extern in (tools/lib/bpf/libbpf.c).
-- @function luaebpf.insn.code:kfunc
function code:kfunc(name)
	return append(self, {code = JMP | insn.jump.CALL, dst = 0, src = 0, off = 0, imm = -1, kfunc = name})
end

--- `dst := the map registered under `name``. The object carries a relocation against the map's
-- symbol, and libbpf replaces both the source register and the immediate with the map's file
-- descriptor, as it does for the `ld_imm64` clang emits.
-- @function luaebpf.insn.code:map
function code:map(dst, name)
	local at = append(self, {code = LD | DW, dst = dst, src = 0, off = 0, imm = 0, map = name})
	append(self, {code = 0, dst = 0, src = 0, off = 0, imm = 0})
	return at
end

--- Returns from the function, with the value in `R0`.
-- @function luaebpf.insn.code:exit
function code:exit()
	return append(self, {code = JMP | insn.jump.EXIT, dst = 0, src = 0, off = 0, imm = 0})
end

---
-- Number of instructions in the buffer.
-- @function luaebpf.insn.code:len
-- @treturn integer
function code:len()
	return self.n
end

---
-- The Lua line each instruction came from, indexed as the buffer is.
-- @function luaebpf.insn.code:sourcelines
-- @treturn table
function code:sourcelines()
	local lines = {}
	for i = 1, self.n do
		lines[i] = self.records[i].line
	end
	return lines
end

---
-- Where each relocation of one kind sits and what it names, for the object to record.
-- @function luaebpf.insn.code:relocations
-- @tparam string kind `"call"` for a BPF-to-BPF call, `"map"` for a map reference, `"kfunc"`
--   for a call into the kernel
-- @treturn table `{at, name}` entries, `at` an index into the buffer
function code:relocations(kind)
	local found = {}
	for i = 1, self.n do
		local name = self.records[i][kind]
		if name ~= nil then
			insert(found, {at = i, name = name})
		end
	end
	return found
end

---
-- The buffer as object bytes, with every jump resolved. A call keeps the `-1` its relocation
-- replaces, as the compiler libbpf was built for leaves it.
-- @function luaebpf.insn.code:pack
-- @treturn string
function code:pack()
	local bytes = {}
	for i = 1, self.n do
		local record = self.records[i]
		local off = record.off or 0
		if record.target ~= nil then
			off = self.labels[record.target] - i
		end
		insert(bytes, pack("<I1I1i2i4", record.code, record.dst | (record.src << 4), off, record.imm))
	end
	return concat(bytes)
end

return insn

