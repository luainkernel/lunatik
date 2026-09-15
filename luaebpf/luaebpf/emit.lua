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
local ROUNDS   <const> = 16
local NAMELEN  <const> = 15  -- BPF_OBJ_NAME_LEN - 1

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
	return -SLOT * (i - NREGS + 1)
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

--- @section calls and returns

local function returns(f, pc, state, i)
	local dropped = f.drop == "verdict"
	if i == nil then
		f.rettype = f.rettype | NIL
		if not dropped then
			f.code:set(reg.R0, f.default)
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
		if f.drop ~= "verdict" then
			code:set(reg.R0, f.default)
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
	local frame = (f.proto.maxstacksize - NREGS) * SLOT
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

local function frame(unit, fn, name, params)
	local f = {
		fn = fn, proto = proto.read(fn), unit = unit, params = params, drop = unit.drop,
		default = unit.default, name = identifier(unit, name),
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
	frame(unit, program.fn, program.name, {CTX})
	return unit.order
end

return emit

