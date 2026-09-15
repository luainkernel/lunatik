--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- The translator: Lua bytecode in, eBPF instructions out.
--
-- A Lua register lives in a callee-saved eBPF register while there are any, and in the frame's
-- stack otherwise, so a value survives a call without the emitter tracking liveness. Every
-- register also carries a type through the function -- integer, boolean, `nil`, or a value only
-- the compiler holds -- because Lua's truth cannot be read off the bits: `0` is true, and
-- `false` and `nil` are both stored as zero.
--
-- The types are reached by walking the bytecode until the entry states stop widening, since a
-- numeric `for` jumps backwards; the code of the last walk is what is kept.
-- @module luaebpf.emit

local insn  = require("luaebpf.insn")
local proto = require("luaebpf.proto")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local insert     = table.insert
local getinfo    = debug.getinfo
local getupvalue = debug.getupvalue

local NREGS    <const> = 4   -- Lua registers 0..3 live in r6..r9; the rest spill to the frame
local FIRST    <const> = reg.R6
local SLOT     <const> = 8
local MAXSTACK <const> = 512 -- MAX_BPF_STACK
local MAXARGS  <const> = 4   -- MAX_BPF_FUNC_REG_ARGS, less the register the abort pointer takes
local NBITS    <const> = 64
local ROUNDS   <const> = 16
local NAMELEN  <const> = 15  -- BPF_OBJ_NAME_LEN - 1
local MININT   <const> = 1 << 63

-- the words every frame reserves: the flag a callee raises through the pointer its caller passed,
-- and where the callee keeps that pointer, since R1-R5 do not survive a nested call
local RESERVED <const> = 2
local ABORTED  <const> = -SLOT
local CALLER   <const> = -SLOT * 2

-- what a Lua register may hold; OTHER is a value the compiler knows and the kernel never sees
local INT     <const> = 1
local BOOL    <const> = 2
local NIL     <const> = 4
local CTX     <const> = 8
local OTHER   <const> = 16
local RUNTIME <const> = INT | BOOL | NIL

local typenames = {[INT] = "number", [BOOL] = "boolean", [NIL] = "nil", [CTX] = "context"}

local opnames = {}
for name, op in pairs(opcodes) do
	opnames[op] = name
end

local emit = {}

-- may_goto landed in v6.9, and the compiler runs on the machine that loads what it emits
local function release()
	local f = io.open("/proc/sys/kernel/osrelease", "r")
	if f == nil then
		return 0, 0
	end
	local major, minor = f:read("l"):match("^(%d+)%.(%d+)")
	f:close()
	return tonumber(major) or 0, tonumber(minor) or 0
end

local major, minor = release()

---
-- Whether the running kernel takes the `may_goto` a loop without a proven bound needs.
-- @field luaebpf.emit.maygoto
emit.maygoto = major > 6 or (major == 6 and minor >= 9)

local function typename(value)
	if value == nil then
		return "undefined value"
	end
	return typenames[value.t] or "value"
end

local function refuse(f, pc, reason, ...)
	error(format("%s:%d: ", f.chunk, f.proto.lines[pc] or f.proto.linedefined) .. format(reason, ...), 0)
end

--- @section the abstract state

-- the join of two abstract values: the types of both, and the compile-time value only where
-- every path agrees on it
local function join(a, b)
	if a == nil or b == nil then
		return a or b
	end
	if a.t == b.t and a.k == b.k then
		return a
	end
	return {t = a.t | b.t, k = a.k == b.k and a.k or nil, name = a.name == b.name and a.name or nil}
end

local function same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.t == b.t and a.k == b.k
end

local function copy(state)
	local out = {}
	for i, value in pairs(state) do
		out[i] = value
	end
	return out
end

-- records the state an edge carries into pc, and notes whether that widened what was there
local function reach(f, pc, state)
	if pc > #f.proto.code then
		return
	end
	local entry = f.entry[pc]
	if entry == nil then
		f.entry[pc] = copy(state)
		f.changed = true
		return
	end
	for i, value in pairs(state) do
		local merged = join(entry[i], value)
		if not same(entry[i], merged) then
			entry[i] = merged
			f.changed = true
		end
	end
end

--- @section Lua registers

local function spilled(i)
	return i >= NREGS
end

local function offset(i)
	return -SLOT * (i - NREGS + 1 + RESERVED)
end

local function getreg(f, pc, state, i, scratch)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	if mask == CTX then
		refuse(f, pc, "the program context cannot be read yet")
	end
	if mask == 0 or (mask & ~RUNTIME) ~= 0 then
		refuse(f, pc, "a %s has no value in the kernel here", typename(value))
	end
	if spilled(i) then
		f.code:load(scratch, reg.FP, offset(i))
		return scratch
	end
	return FIRST + i
end

local function setreg(f, i, src)
	if spilled(i) then
		f.code:store(reg.FP, offset(i), src)
	else
		f.code:alu(alu.MOV, FIRST + i, src)
	end
end

local function setimm(f, i, value)
	if spilled(i) then
		f.code:set(reg.R1, value)
		f.code:store(reg.FP, offset(i), reg.R1)
	else
		f.code:set(FIRST + i, value)
	end
end

-- reads a Lua register into a scratch register the caller may then destroy
local function into(f, pc, state, i, scratch)
	local from = getreg(f, pc, state, i, scratch)
	if from ~= scratch then
		f.code:alu(alu.MOV, scratch, from)
	end
	return scratch
end

local function isinteger(value)
	return value ~= nil and value.t == INT
end

-- a value the file body computed becomes a constant of the program; only what the kernel can
-- hold takes a register
local function resolve(f, pc, state, i, value, name)
	local kind = type(value)
	if kind == "number" then
		setimm(f, i, value)
		state[i] = {t = INT, k = value, name = name}
	elseif kind == "boolean" then
		setimm(f, i, value and 1 or 0)
		state[i] = {t = BOOL, k = value, name = name}
	elseif value == nil then
		setimm(f, i, 0)
		state[i] = {t = NIL, name = name}
	elseif kind == "table" or kind == "function" or kind == "string" then
		state[i] = {t = OTHER, k = value, name = name}
	else
		refuse(f, pc, "'%s' is a %s, which a compiled function cannot hold", name or "value", kind)
	end
end

local function upvalue(f, pc, i)
	local name, value = getupvalue(f.fn, i + 1)
	if name == nil then
		refuse(f, pc, "upvalue #%d does not exist", i + 1)
	end
	return value, name
end

local function constant(f, pc, i)
	if i >= f.proto.nk then
		refuse(f, pc, "constant #%d does not exist", i + 1)
	end
	return f.proto.k[i + 1]
end

--- @section control flow

local function labelof(f, pc)
	local label = f.labels[pc]
	if label == nil then
		refuse(f, pc, "a jump leaves the function")
	end
	return label
end

-- the tail taken where the interpreter would raise: the program's default verdict in its own
-- frame, and the flag that carries the verdict one frame up everywhere else
local function abort(f)
	if f.aborted == nil then
		f.aborted = f.code:label()
	end
	return f.aborted
end

local function jumptarget(f, pc)
	local ins = f.proto.code[pc]
	if ins == nil or ins.op ~= opcodes.JMP then
		refuse(f, pc - 1, "a test is not followed by a jump")
	end
	local target = pc + ins.sj + 1
	if target <= pc then
		refuse(f, pc, "'while' and 'repeat' are not compiled yet")
	end
	return target
end

-- a test whose outcome the types already decide is the jump, or nothing at all
local function settled(f, pc, state, taken)
	if not taken then
		reach(f, pc + 2, state)
		return false
	end
	local target = jumptarget(f, pc + 1)
	f.code:jump(labelof(f, target))
	reach(f, target, state)
	return false
end

local function testjump(f, pc, state, op, dst, src)
	local target = jumptarget(f, pc + 1)
	f.code:branch(op, dst, src, labelof(f, target))
	reach(f, target, state)
	reach(f, pc + 2, state)
	return false
end

--- @section loads

local ops = {}

local function moveslot(f, pc, state, a, b)
	local value = state[b]
	if value ~= nil and (value.t & RUNTIME) ~= 0 then
		setreg(f, a, getreg(f, pc, state, b, reg.R1))
	end
	state[a] = value
end

function ops.MOVE(f, pc, ins, state)
	moveslot(f, pc, state, ins.a, ins.b)
end

function ops.LOADI(f, pc, ins, state)
	resolve(f, pc, state, ins.a, ins.sbx)
end

function ops.LOADK(f, pc, ins, state)
	resolve(f, pc, state, ins.a, constant(f, pc, ins.bx))
end

function ops.LOADKX(f, pc, ins, state)
	local extra = f.proto.code[pc + 1]
	if extra == nil or extra.op ~= opcodes.EXTRAARG then
		refuse(f, pc, "LOADKX is not followed by EXTRAARG")
	end
	resolve(f, pc, state, ins.a, constant(f, pc, extra.ax))
	reach(f, pc + 2, state)
	return false
end

function ops.LOADFALSE(f, pc, ins, state)
	resolve(f, pc, state, ins.a, false)
end

function ops.LOADTRUE(f, pc, ins, state)
	resolve(f, pc, state, ins.a, true)
end

function ops.LFALSESKIP(f, pc, ins, state)
	resolve(f, pc, state, ins.a, false)
	f.code:jump(labelof(f, pc + 2))
	reach(f, pc + 2, state)
	return false
end

function ops.LOADNIL(f, pc, ins, state)
	for i = ins.a, ins.a + ins.b do
		resolve(f, pc, state, i, nil)
	end
end

function ops.GETUPVAL(f, pc, ins, state)
	local value, name = upvalue(f, pc, ins.b)
	resolve(f, pc, state, ins.a, value, name)
end

local function lookup(f, pc, container, key, name)
	if container == nil or type(container.k) ~= "table" then
		refuse(f, pc, "'%s' is read from a value the compiler cannot resolve", name)
	end
	return container.k[key]
end

-- a field of any upvalue table is this opcode too, not only a global, which is _ENV's field
function ops.GETTABUP(f, pc, ins, state)
	local env, upname = upvalue(f, pc, ins.b)
	local key = tostring(constant(f, pc, ins.c))
	local value = lookup(f, pc, {k = env}, key, upname)
	if value == nil then
		local read = upname == "_ENV" and format("global '%s'", key) or format("'%s.%s'", upname, key)
		refuse(f, pc, "%s is not a compile-time value", read)
	end
	resolve(f, pc, state, ins.a, value, key)
end

function ops.GETFIELD(f, pc, ins, state)
	local key = tostring(constant(f, pc, ins.c))
	local container = state[ins.b]
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key, name), key)
end

function ops.GETI(f, pc, ins, state)
	local container = state[ins.b]
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, ins.c, name))
end

function ops.GETTABLE(f, pc, ins, state)
	local key = state[ins.c]
	local container = state[ins.b]
	local name = container ~= nil and container.name or "a table"
	if key == nil or key.k == nil then
		refuse(f, pc, "'%s' is indexed by a value the compiler cannot resolve", name)
	end
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key.k, name))
end

--- @section arithmetic

-- Lua's floor division: the quotient is corrected toward minus infinity when the operands'
-- signs differ, a divisor of -1 is a negation (which mininteger needs), and a divisor of zero
-- raises, so the program takes its default verdict
local function floordiv(f)
	local code = f.code
	local negate, done = code:label(), code:label()
	if f.drop ~= "divisor" then
		code:branchi(jump.JEQ, reg.R2, 0, abort(f))
	end
	code:branchi(jump.JEQ, reg.R2, -1, negate)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:alu(alu.MOV, reg.R4, reg.R1)
	code:sdiv(alu.MOD, reg.R4, reg.R2)
	code:sdiv(alu.DIV, reg.R1, reg.R2)
	code:branchi(jump.JEQ, reg.R4, 0, done)
	code:alu(alu.XOR, reg.R3, reg.R2)
	code:branchi(jump.JSGE, reg.R3, 0, done)
	code:alui(alu.ADD, reg.R1, -1)
	code:jump(done)
	code:place(negate)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:set(reg.R1, 0)
	code:alu(alu.SUB, reg.R1, reg.R3)
	code:place(done)
end

-- Lua's modulo: the remainder takes the divisor's sign, and a divisor of -1 is zero
local function floormod(f)
	local code = f.code
	local zero, done = code:label(), code:label()
	if f.drop ~= "divisor" then
		code:branchi(jump.JEQ, reg.R2, 0, abort(f))
	end
	code:branchi(jump.JEQ, reg.R2, -1, zero)
	code:sdiv(alu.MOD, reg.R1, reg.R2)
	code:branchi(jump.JEQ, reg.R1, 0, done)
	code:alu(alu.MOV, reg.R3, reg.R1)
	code:alu(alu.XOR, reg.R3, reg.R2)
	code:branchi(jump.JSGE, reg.R3, 0, done)
	code:alu(alu.ADD, reg.R1, reg.R2)
	code:jump(done)
	code:place(zero)
	code:set(reg.R1, 0)
	code:place(done)
end

-- luaV_shiftl: logical in both directions, zero past the word, and a negative count shifts the
-- other way; eBPF masks the count to 63, so the range is tested rather than trusted
local function shiftl(f)
	local code = f.code
	local right, zero, done = code:label(), code:label(), code:label()
	code:branchi(jump.JSLT, reg.R2, 0, right)
	code:branchi(jump.JSGE, reg.R2, NBITS, zero)
	code:alu(alu.LSH, reg.R1, reg.R2)
	code:jump(done)
	code:place(right)
	code:branchi(jump.JSLE, reg.R2, -NBITS, zero)
	code:neg(reg.R2)
	code:alu(alu.RSH, reg.R1, reg.R2)
	code:jump(done)
	code:place(zero)
	code:set(reg.R1, 0)
	code:place(done)
end

-- every binary operator over R1 and R2, leaving the result in R1
local binops = {}

function binops.ADD(f) f.code:alu(alu.ADD, reg.R1, reg.R2) end
function binops.SUB(f) f.code:alu(alu.SUB, reg.R1, reg.R2) end
function binops.MUL(f) f.code:alu(alu.MUL, reg.R1, reg.R2) end
function binops.BAND(f) f.code:alu(alu.AND, reg.R1, reg.R2) end
function binops.BOR(f) f.code:alu(alu.OR, reg.R1, reg.R2) end
function binops.BXOR(f) f.code:alu(alu.XOR, reg.R1, reg.R2) end
function binops.IDIV(f) floordiv(f) end
function binops.MOD(f) floormod(f) end
function binops.SHL(f) shiftl(f) end

function binops.SHR(f)
	f.code:neg(reg.R2)
	shiftl(f)
end

-- the kernel calls no metamethod, so every operand an arithmetic opcode reads is a number
local function numbers(f, pc, ...)
	for _, value in ipairs({...}) do
		if not isinteger(value) then
			refuse(f, pc, "attempt to perform arithmetic on a %s value", typename(value))
		end
	end
end

-- R[A] := R[B] op R[C], and R[A] := R[B] op <constant>; a constant takes a register too, since
-- eBPF's immediate is 32 bits and Lua's constants are not
local function register(f, pc, ins, state, op)
	into(f, pc, state, ins.b, reg.R1)
	into(f, pc, state, ins.c, reg.R2)
	numbers(f, pc, state[ins.b], state[ins.c])
	binops[op](f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

local function immediate(f, pc, ins, state, op, value)
	into(f, pc, state, ins.b, reg.R1)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R2, value)
	binops[op](f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

local function numeric(f, pc, value)
	if type(value) ~= "number" then
		refuse(f, pc, "attempt to perform arithmetic on a %s constant", type(value))
	end
	return value
end

function ops.ADD(f, pc, ins, state) register(f, pc, ins, state, "ADD") end
function ops.SUB(f, pc, ins, state) register(f, pc, ins, state, "SUB") end
function ops.MUL(f, pc, ins, state) register(f, pc, ins, state, "MUL") end
function ops.MOD(f, pc, ins, state) register(f, pc, ins, state, "MOD") end
function ops.IDIV(f, pc, ins, state) register(f, pc, ins, state, "IDIV") end
function ops.BAND(f, pc, ins, state) register(f, pc, ins, state, "BAND") end
function ops.BOR(f, pc, ins, state) register(f, pc, ins, state, "BOR") end
function ops.BXOR(f, pc, ins, state) register(f, pc, ins, state, "BXOR") end
function ops.SHL(f, pc, ins, state) register(f, pc, ins, state, "SHL") end
function ops.SHR(f, pc, ins, state) register(f, pc, ins, state, "SHR") end

function ops.ADDK(f, pc, ins, state)
	immediate(f, pc, ins, state, "ADD", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.SUBK(f, pc, ins, state)
	immediate(f, pc, ins, state, "SUB", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.MULK(f, pc, ins, state)
	immediate(f, pc, ins, state, "MUL", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.MODK(f, pc, ins, state)
	immediate(f, pc, ins, state, "MOD", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.IDIVK(f, pc, ins, state)
	immediate(f, pc, ins, state, "IDIV", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.BANDK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BAND", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.BORK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BOR", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.BXORK(f, pc, ins, state)
	immediate(f, pc, ins, state, "BXOR", numeric(f, pc, constant(f, pc, ins.c)))
end

function ops.ADDI(f, pc, ins, state)
	immediate(f, pc, ins, state, "ADD", ins.sc)
end

-- the constant is the left operand of a SHLI, and a SHRI's count is negated into a shift left
function ops.SHLI(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R2)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R1, ins.sc)
	shiftl(f)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

function ops.SHRI(f, pc, ins, state)
	immediate(f, pc, ins, state, "SHL", -ins.sc)
end

function ops.UNM(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R2)
	numbers(f, pc, state[ins.b])
	f.code:set(reg.R1, 0)
	f.code:alu(alu.SUB, reg.R1, reg.R2)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

function ops.BNOT(f, pc, ins, state)
	into(f, pc, state, ins.b, reg.R1)
	numbers(f, pc, state[ins.b])
	f.code:alui(alu.XOR, reg.R1, -1)
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

-- the truth of a register as Lua reads it: 0 is true, and only false and nil are not. nil when
-- the types leave it to a test at run time.
local function truth(f, pc, state, i)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	if mask == INT then
		return true
	end
	if mask == NIL then
		return false
	end
	if mask == 0 or (mask & ~(BOOL | NIL)) ~= 0 then
		refuse(f, pc, "a %s has no truth value in a compiled function", typename(value))
	end
	return nil
end

function ops.NOT(f, pc, ins, state)
	local known = truth(f, pc, state, ins.b)
	if known ~= nil then
		resolve(f, pc, state, ins.a, not known)
		return
	end
	local one, done = f.code:label(), f.code:label()
	into(f, pc, state, ins.b, reg.R1)
	f.code:branchi(jump.JEQ, reg.R1, 0, one)
	f.code:set(reg.R2, 0)
	f.code:jump(done)
	f.code:place(one)
	f.code:set(reg.R2, 1)
	f.code:place(done)
	setreg(f, ins.a, reg.R2)
	state[ins.a] = {t = BOOL}
end

-- the metamethod opcode, which the VM skips when both operands were numbers; 'numbers' reads
-- them where they are still live, since the opcode before this one writes over one of them
local function skipped() end

ops.MMBIN, ops.MMBINI, ops.MMBINK = skipped, skipped, skipped

--- @section comparisons and branches

local relations = {
	EQ = {[true] = jump.JEQ, [false] = jump.JNE},
	LT = {[true] = jump.JSLT, [false] = jump.JSGE},
	LE = {[true] = jump.JSLE, [false] = jump.JSGT},
	GT = {[true] = jump.JSGT, [false] = jump.JSLE},
	GE = {[true] = jump.JSGE, [false] = jump.JSLT},
}

local function ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		return
	end
	if not isinteger(a) or not isinteger(b) then
		refuse(f, pc, "attempt to compare a %s with a %s", typename(a), typename(b))
	end
end

-- whether the type names one Lua type. A join widens a register to several, and the bits say
-- which for none of them: false, nil and the integer zero are one word.
local function exact(value)
	local mask = value ~= nil and value.t or 0
	return mask ~= 0 and (mask & (mask - 1)) == 0
end

-- whether the compiler holds the value itself, rather than the register
local function held(value)
	return value ~= nil and (value.k ~= nil or value.t == NIL)
end

-- the type mask of a bytecode constant
local function typeof(value)
	local kind = type(value)
	if kind == "number" then
		return INT
	end
	if kind == "boolean" then
		return BOOL
	end
	if value == nil then
		return NIL
	end
	return OTHER
end

local function undecidable(f, pc, a, b)
	refuse(f, pc, "a %s cannot be compared with a %s here", typename(a), typename(b))
end

-- the answer Lua's '==' is pinned to, and nil where the registers carry it
local function equality(f, pc, a, b)
	if exact(a) and exact(b) then
		if a.t ~= b.t then
			return false -- Lua's '==' is false across types
		end
		if a.t == INT or a.t == BOOL then
			return nil
		end
	end
	if held(a) and held(b) then
		return a.k == b.k
	end
	undecidable(f, pc, a, b)
end

local function compare(f, pc, ins, state, relation, b)
	local a = state[ins.a]
	ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		local answer = equality(f, pc, a, b)
		if answer ~= nil then
			return settled(f, pc, state, answer == ins.k)
		end
	end
	into(f, pc, state, ins.a, reg.R1)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1, getreg(f, pc, state, ins.b, reg.R2))
end

function ops.EQ(f, pc, ins, state) return compare(f, pc, ins, state, "EQ", state[ins.b]) end
function ops.LT(f, pc, ins, state) return compare(f, pc, ins, state, "LT", state[ins.b]) end
function ops.LE(f, pc, ins, state) return compare(f, pc, ins, state, "LE", state[ins.b]) end

local function compareconst(f, pc, ins, state, relation, value)
	local a, b = state[ins.a], {t = typeof(value), k = value}
	ordered(f, pc, relation, a, b)
	if relation == "EQ" then
		local answer = equality(f, pc, a, b)
		if answer ~= nil then
			return settled(f, pc, state, answer == ins.k)
		end
	end
	local operand = value
	if b.t == BOOL then -- the register carries the 1 or 0 'resolve' stored for it
		operand = value and 1 or 0
	end
	into(f, pc, state, ins.a, reg.R1)
	f.code:set(reg.R2, operand)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1, reg.R2)
end

function ops.EQI(f, pc, ins, state) return compareconst(f, pc, ins, state, "EQ", ins.sb) end
function ops.LTI(f, pc, ins, state) return compareconst(f, pc, ins, state, "LT", ins.sb) end
function ops.LEI(f, pc, ins, state) return compareconst(f, pc, ins, state, "LE", ins.sb) end
function ops.GTI(f, pc, ins, state) return compareconst(f, pc, ins, state, "GT", ins.sb) end
function ops.GEI(f, pc, ins, state) return compareconst(f, pc, ins, state, "GE", ins.sb) end

function ops.EQK(f, pc, ins, state)
	return compareconst(f, pc, ins, state, "EQ", constant(f, pc, ins.b))
end

function ops.TEST(f, pc, ins, state)
	local known = truth(f, pc, state, ins.a)
	if known ~= nil then
		return settled(f, pc, state, known == ins.k)
	end
	into(f, pc, state, ins.a, reg.R1)
	f.code:set(reg.R2, 0)
	return testjump(f, pc, state, relations.EQ[not ins.k], reg.R1, reg.R2)
end

function ops.TESTSET(f, pc, ins, state)
	local known = truth(f, pc, state, ins.b)
	if known ~= nil then
		if known ~= ins.k then
			reach(f, pc + 2, state)
			return false
		end
		moveslot(f, pc, state, ins.a, ins.b)
		local target = jumptarget(f, pc + 1)
		f.code:jump(labelof(f, target))
		reach(f, target, state)
		return false
	end
	local skip = f.code:label()
	into(f, pc, state, ins.b, reg.R1)
	f.code:branchi(ins.k and jump.JEQ or jump.JNE, reg.R1, 0, skip)
	local taken = copy(state)
	setreg(f, ins.a, reg.R1)
	taken[ins.a] = state[ins.b]
	local target = jumptarget(f, pc + 1)
	f.code:jump(labelof(f, target))
	f.code:place(skip)
	reach(f, target, taken)
	reach(f, pc + 2, state)
	return false
end

function ops.JMP(f, pc, ins, state)
	local target = jumptarget(f, pc)
	f.code:jump(labelof(f, target))
	reach(f, target, state)
	return false
end

--- @section the numeric for

-- a bound the compiler proved: the three control registers carry a value it knows, so the count
-- is a constant and the verifier can walk the loop instead of being handed an iteration budget
local function bounded(state, a)
	for i = a, a + 2 do
		local value = state[i]
		if value == nil or value.t ~= INT or value.k == nil then
			return false
		end
	end
	return true
end

local function ult(a, b)
	return (a ~ MININT) < (b ~ MININT)
end

-- the iteration count is unsigned, and Lua's '//' is not; halving first keeps the dividend
-- positive, and one correction step recovers the bit that shifted out
local function udiv(a, b)
	if b < 0 then
		return ult(a, b) and 0 or 1
	end
	if a >= 0 then
		return a // b
	end
	local q = ((a >> 1) // b) << 1
	if not ult(a - q * b, b) then
		q = q + 1
	end
	return q
end

local function counted(f, pc, ins, state, a)
	local init, limit, step = state[a].k, state[a + 1].k, state[a + 2].k
	if (step > 0 and init > limit) or (step < 0 and init < limit) then
		f.code:jump(labelof(f, pc + ins.bx + 2))
		reach(f, pc + ins.bx + 2, state)
		return true
	end
	if step > 0 then
		setimm(f, a, udiv(limit - init, step))
	else
		setimm(f, a, udiv(init - limit, -step))
	end
	setimm(f, a + 1, step)
	setimm(f, a + 2, init)
	return false
end

-- as lvm.c's forprep does, the iterations are counted up front, so the loop cannot run past its
-- limit by overflowing it
local function counting(f, pc, ins, state, a)
	local code = f.code
	local skip = labelof(f, pc + ins.bx + 2)
	local descending, divide, store = code:label(), code:label(), code:label()
	into(f, pc, state, a, reg.R1)
	into(f, pc, state, a + 1, reg.R2)
	into(f, pc, state, a + 2, reg.R3)
	if state[a + 2].k == nil then
		code:branchi(jump.JEQ, reg.R3, 0, abort(f))
	end
	code:alu(alu.MOV, reg.R5, reg.R3)
	code:branchi(jump.JSLT, reg.R3, 0, descending)
	code:branch(jump.JSGT, reg.R1, reg.R2, skip)
	code:alu(alu.SUB, reg.R2, reg.R1)
	code:jump(divide)
	code:place(descending)
	code:branch(jump.JSLT, reg.R1, reg.R2, skip)
	code:alu(alu.MOV, reg.R4, reg.R1)
	code:alu(alu.SUB, reg.R4, reg.R2)
	code:alu(alu.MOV, reg.R2, reg.R4)
	code:neg(reg.R3)
	code:place(divide)
	code:branchi(jump.JEQ, reg.R3, 1, store)
	code:alu(alu.DIV, reg.R2, reg.R3)
	code:place(store)
	setreg(f, a, reg.R2)
	setreg(f, a + 1, reg.R5)
	setreg(f, a + 2, reg.R1)
end

function ops.FORPREP(f, pc, ins, state)
	local a = ins.a
	for i = a, a + 2 do
		if not isinteger(state[i]) then
			refuse(f, pc, "'for' takes numbers, not a %s", typename(state[i]))
		end
	end
	if state[a + 2].k == 0 then
		refuse(f, pc, "'for' step is zero")
	end
	local proven = bounded(state, a)
	f.bounded[pc + ins.bx + 1] = proven
	local step = state[a + 2].k
	local never = proven and counted(f, pc, ins, state, a)
	if not never then
		if not proven then
			counting(f, pc, ins, state, a)
		end
		state[a] = {t = INT}
		state[a + 1] = {t = INT, k = step}
		state[a + 2] = {t = INT}
		reach(f, pc + ins.bx + 2, state)
		reach(f, pc + 1, state)
	end
	return false
end

function ops.FORLOOP(f, pc, ins, state)
	local a, code = ins.a, f.code
	local after = labelof(f, pc + 1)
	if not f.bounded[pc] then
		if not emit.maygoto then
			refuse(f, pc, "a 'for' the compiler cannot bound needs may_goto, which this kernel lacks")
		end
		if f.drop ~= "maygoto" then
			code:maygoto(after)
		end
	end
	into(f, pc, state, a, reg.R1)
	code:branchi(jump.JEQ, reg.R1, 0, after)
	code:alui(alu.ADD, reg.R1, -1)
	setreg(f, a, reg.R1)
	into(f, pc, state, a + 2, reg.R2)
	code:alu(alu.ADD, reg.R2, getreg(f, pc, state, a + 1, reg.R3))
	setreg(f, a + 2, reg.R2)
	code:jump(labelof(f, pc + 1 - ins.bx))
	state[a] = {t = INT}
	state[a + 2] = {t = INT}
	reach(f, pc + 1 - ins.bx, state)
	reach(f, pc + 1, state)
	return false
end

--- @section calls and returns

local function returns(f, pc, state, i)
	local dropped = f.drop == "verdict"
	if i == nil then
		f.rettype = f.rettype | NIL
		if not dropped then
			f.code:set(reg.R0, f.isprogram and f.default or 0)
		end
	else
		f.rettype = f.rettype | state[i].t
		if not dropped then
			f.code:alu(alu.MOV, reg.R0, getreg(f, pc, state, i, reg.R0))
		end
	end
	f.code:exit()
	return false
end

function ops.RETURN(f, pc, ins, state)
	if ins.b == 0 or ins.b > 2 then
		refuse(f, pc, "a compiled function returns at most one value")
	end
	return returns(f, pc, state, ins.b == 2 and ins.a or nil)
end

function ops.RETURN0(f, pc, ins, state)
	return returns(f, pc, state, nil)
end

function ops.RETURN1(f, pc, ins, state)
	return returns(f, pc, state, ins.a)
end

function ops.CALL(f, pc, ins, state)
	local callee = state[ins.a]
	if callee == nil or type(callee.k) ~= "function" then
		refuse(f, pc, "a call through a value the compiler cannot resolve")
	end
	if getinfo(callee.k, "S").what == "C" then
		refuse(f, pc, "'%s' is not a Lua function this program file declares", callee.name or "?")
	end
	if ins.b == 0 or ins.c == 0 then
		refuse(f, pc, "a call with a variable number of values cannot be compiled")
	end
	local nargs = ins.b - 1
	if nargs > MAXARGS then
		refuse(f, pc, "a compiled function takes at most %d arguments, not %d", MAXARGS, nargs)
	end
	local params = {}
	for i = 1, nargs do
		if not isinteger(state[ins.a + i]) then
			refuse(f, pc, "argument #%d is a %s, and a compiled call passes numbers",
				i, typename(state[ins.a + i]))
		end
		params[i] = INT
	end
	local target = emit.subprogram(f, pc, callee.k, callee.name, params)
	for i = 1, nargs do
		into(f, pc, state, ins.a + i, reg.R0 + i)
	end
	f.code:storei(reg.FP, ABORTED, 0)
	f.code:alu(alu.MOV, reg.R1 + nargs, reg.FP)
	f.code:alui(alu.ADD, reg.R1 + nargs, ABORTED)
	f.code:call(target.name)
	f.code:load(reg.R1, reg.FP, ABORTED)
	f.code:branchi(jump.JNE, reg.R1, 0, abort(f))
	if ins.c > 1 then
		setreg(f, ins.a, reg.R0)
		state[ins.a] = {t = target.rettype}
	end
	-- a compiled function returns one value, so Lua fills every further result asked for with nil
	for i = ins.a + 1, ins.a + ins.c - 2 do
		resolve(f, pc, state, i, nil)
	end
end

--- @section the walk

local refusals = {
	SETUPVAL = "an upvalue cannot be assigned in a compiled function",
	SETTABUP = "a global cannot be assigned in a compiled function",
	SETTABLE = "a table cannot be written in a compiled function",
	SETI = "a table cannot be written in a compiled function",
	SETFIELD = "a table cannot be written in a compiled function",
	NEWTABLE = "a table constructor cannot run in the kernel; build it in the file body",
	SETLIST = "a table constructor cannot run in the kernel; build it in the file body",
	SELF = "a method call cannot be compiled",
	LEN = "'#' cannot be applied in a compiled function",
	CONCAT = "'..' cannot be applied in a compiled function",
	CLOSE = "a to-be-closed variable cannot be compiled",
	TBC = "a to-be-closed variable cannot be compiled",
	CLOSURE = "a closure cannot be created in a compiled function",
	TAILCALL = "a tail call cannot be compiled",
	VARARG = "a vararg function cannot be compiled",
	VARARGPREP = "a vararg function cannot be compiled",
	GETVARG = "a vararg function cannot be compiled",
	TFORPREP = "a generic 'for' cannot be compiled",
	TFORCALL = "a generic 'for' cannot be compiled",
	TFORLOOP = "a generic 'for' cannot be compiled",
	ERRNNIL = "a 'global' declaration cannot be compiled",
	EXTRAARG = "EXTRAARG reached on its own",
}

local handlers = {}
for name, op in pairs(opcodes) do
	handlers[op] = ops[name]
end

local function walk(f)
	local code = insn.new()
	f.code = code
	f.labels = {}
	f.aborted = nil
	f.rettype = 0
	for pc = 1, #f.proto.code do
		f.labels[pc] = code:label()
	end
	local start = f.entry[1] or {}
	f.entry[1] = start
	code:source(f.proto.linedefined)
	if not f.isprogram then
		code:store(reg.FP, CALLER, reg.R1 + #f.params)
	end
	for i = 0, f.proto.numparams - 1 do
		setreg(f, i, reg.R1 + i)
		start[i] = {t = f.params[i + 1]}
	end
	for pc = 1, #f.proto.code do
		local entry = f.entry[pc]
		if entry ~= nil then
			local state, ins = copy(entry), f.proto.code[pc]
			local handler = handlers[ins.op]
			code:place(f.labels[pc])
			code:source(f.proto.lines[pc])
			if handler == nil then
				local opname = opnames[ins.op]
				refuse(f, pc, "%s", refusals[opname] or opname .. " cannot be compiled")
			end
			if handler(f, pc, ins, state) ~= false then
				reach(f, pc + 1, state)
			end
		end
	end
	if f.aborted ~= nil then
		code:source(f.proto.lastlinedefined)
		code:place(f.aborted)
		if f.isprogram then
			if f.drop ~= "verdict" then
				code:set(reg.R0, f.default)
			end
		else
			code:load(reg.R1, reg.FP, CALLER)
			code:storei(reg.R1, 0, 1)
			-- the verifier cannot pair the flag with the path, so R0 is read on the fall-through too
			code:set(reg.R0, 0)
		end
		code:exit()
	end
	return code
end

---
-- Lowers one Lua function into a code buffer, left on the frame's `code`.
-- @function luaebpf.emit.lower
-- @tparam table f the frame: `fn`, `proto`, `chunk`, `params`, `default`, `isprogram`, `drop`
-- @raise `<file>:<line>: <reason>` for every construct the subset refuses
function emit.lower(f)
	local frame = (f.proto.maxstacksize - NREGS + RESERVED) * SLOT
	if frame > MAXSTACK then
		refuse(f, 1, "the function needs %d bytes of stack, over the %d eBPF allows", frame, MAXSTACK)
	end
	if f.proto.isvararg then
		refuse(f, 1, "a vararg function cannot be compiled")
	end
	f.entry = {}
	f.bounded = {}
	for _ = 1, ROUNDS do
		f.changed = false
		walk(f)
		if not f.changed then
			return
		end
	end
	refuse(f, 1, "the compiler did not settle on the types of this function")
end

--- @section the program

-- the object names functions, so two Lua locals of the same name get one name each
local function identifier(unit, name)
	local base = (name or "fn"):gsub("[^%w_]", "_"):sub(1, NAMELEN)
	local unique, n = base, 1
	while unit.names[unique] do
		n = n + 1
		unique = base:sub(1, NAMELEN - #tostring(n) - 1) .. "_" .. n
	end
	unit.names[unique] = true
	return unique
end

local function frame(unit, fn, read, name, params, isprogram)
	local f = {
		fn = fn, proto = read, unit = unit, params = params, drop = unit.drop,
		default = unit.default, isprogram = isprogram, name = identifier(unit, name),
	}
	f.chunk = f.proto.source:gsub("^@", "")
	unit.lowering[fn] = true
	unit.functions[fn] = f
	insert(unit.order, f)
	emit.lower(f)
	unit.lowering[fn] = nil
	return f
end

---
-- Compiles the function a call resolved to, once per program, as a BPF-to-BPF subprogram.
-- @function luaebpf.emit.subprogram
-- @tparam table f the calling frame
-- @tparam integer pc the call site, for the message
-- @tparam function fn the callee
-- @tparam[opt] string name what the caller knows the callee as
-- @tparam table params the type of each argument
-- @treturn table the callee's frame
-- @raise `recursion through '<name>'`, `'<name>' is called with <n> arguments and compiled
--   with <m>`, or `'<name>' takes <n> arguments and is called with <m>`
function emit.subprogram(f, pc, fn, name, params)
	local unit = f.unit
	if unit.lowering[fn] then
		refuse(f, pc, "recursion through '%s'", name or "a function")
	end
	local compiled = unit.functions[fn]
	if compiled ~= nil then
		if #compiled.params ~= #params then
			refuse(f, pc, "'%s' is called with %d arguments and compiled with %d",
				compiled.name, #params, #compiled.params)
		end
		return compiled
	end
	local read = proto.read(fn)
	-- without this the prologue reads a register the call never set, and the verifier names it
	if read.numparams > #params then
		refuse(f, pc, "'%s' takes %d arguments and is called with %d", name or "a function",
			read.numparams, #params)
	end
	return frame(unit, fn, read, name, params, false)
end

---
-- Compiles one program: its function, and every function that function reaches.
-- @function luaebpf.emit.program
-- @tparam table program `{name, fn, default, drop, names}`
-- @treturn table the frames, the program's own first
-- @raise `a program takes one argument, the context`, and `<file>:<line>: <reason>` for every
--   construct the subset refuses
function emit.program(program)
	local unit = {
		functions = {}, order = {}, lowering = {}, names = program.names or {},
		default = program.default, drop = program.drop,
	}
	local read = proto.read(program.fn)
	if read.numparams > 1 then
		error(format("%s:%d: a program takes one argument, the context",
			(read.source:gsub("^@", "")), read.linedefined), 0)
	end
	frame(unit, program.fn, read, program.name, {CTX}, true)
	return unit.order
end

return emit

