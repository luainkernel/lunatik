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
--
-- Each instruction is lowered by the module beside this one whose member carries its opcode's
-- name, over what `luaebpf.emit.frame` holds.
-- @module luaebpf.emit

local config     = require("lunatik.config")
local insn       = require("luaebpf.insn")
local proto      = require("luaebpf.proto")
local frame      = require("luaebpf.emit.frame")
local context    = require("luaebpf.emit.context")
local loads      = require("luaebpf.emit.loads")
local arithmetic = require("luaebpf.emit.arithmetic")
local branch     = require("luaebpf.emit.branch")
local forloop    = require("luaebpf.emit.forloop")
local call       = require("luaebpf.emit.call")

local reg     = insn.reg
local opcodes = proto.opcodes
local format  = string.format
local insert  = table.insert
local copy, reach, refuse, setreg = frame.copy, frame.reach, frame.refuse, frame.setreg

local MAXSTACK <const> = 512 -- MAX_BPF_STACK
local ROUNDS   <const> = 16
local NAMELEN  <const> = 15  -- BPF_OBJ_NAME_LEN - 1
local MAYGOTO  <const> = 6 << 16 | 9 << 8 -- KERNEL_VERSION(6, 9, 0): v6.9 and later take may_goto

local CALLER   <const> = frame.CALLER
local CTX      <const> = context.CTX
local NREGS    <const> = frame.NREGS
local RESERVED <const> = frame.RESERVED
local SLOT     <const> = frame.SLOT

local typenames = frame.typenames

local opnames = {}
for name, op in pairs(opcodes) do
	opnames[op] = name
end

local emit = {}

---
-- Whether the kernel Lunatik is built for, whose version `lunatik.config` carries, takes the
-- `may_goto` a loop without a proven bound needs.
-- @field luaebpf.emit.maygoto
emit.maygoto = config.kernel_version >= MAYGOTO

---
-- Whether the kernel Lunatik is built for lets a program read a word at any address, as its
-- `HAVE_EFFICIENT_UNALIGNED_ACCESS`, which `lunatik.config` carries, says. Without it the
-- verifier refuses a packet read, or a read of a struct map value's field, wider than a byte at
-- an offset it cannot prove aligned.
-- @field luaebpf.emit.unaligned
emit.unaligned = config.efficient_unaligned_access

---
-- Whether the kernel Lunatik is built for is big-endian, as its `CONFIG_CPU_BIG_ENDIAN`, which
-- `lunatik.config` carries, says. The object is written in that byte order, and a map spec is read
-- in it.
-- @field luaebpf.emit.bigendian
emit.bigendian = config.cpu_big_endian

--- @section the walk

local refusals = {
	SETUPVAL = "an upvalue cannot be assigned in a compiled function",
	NEWTABLE = "a table constructor cannot run in the kernel; build it in the file body",
	SETLIST = "a table constructor cannot run in the kernel; build it in the file body",
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
	handlers[op] = loads[name] or arithmetic[name] or branch[name] or forloop[name] or call[name]
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
-- @local
-- @function lower
-- @tparam table f the frame: `fn`, `proto`, `chunk`, `params`, `default`, `isprogram`, `drop`
-- @raise `<file>:<line>: <reason>` for every construct the subset refuses
local function lower(f)
	local stack = (f.proto.maxstacksize - NREGS + RESERVED) * SLOT
	if stack > MAXSTACK then
		refuse(f, 1, "the function needs %d bytes of stack, over the %d eBPF allows", stack, MAXSTACK)
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

local function compile(unit, fn, read, name, params, isprogram)
	local f = {
		fn = fn, proto = read, unit = unit, params = params, drop = unit.drop,
		default = unit.default, isprogram = isprogram, name = identifier(unit, name),
	}
	f.chunk = f.proto.source:gsub("^@", "")
	unit.lowering[fn] = true
	unit.functions[fn] = f
	insert(unit.order, f)
	lower(f)
	unit.lowering[fn] = nil
	return f
end

---
-- Compiles the function a call resolved to, once per program, as a BPF-to-BPF subprogram.
-- @local
-- @function subprogram
-- @tparam table f the calling frame
-- @tparam integer pc the call site, for the message
-- @tparam function fn the callee
-- @tparam[opt] string name what the caller knows the callee as
-- @tparam table params the type of each argument
-- @treturn table the callee's frame
-- @raise `recursion through '<name>'`, `'<name>' is called with <n> arguments and compiled
--   with <m>`, `'<name>' is called with a <type> and compiled with a <type>`, or `'<name>'
--   takes <n> arguments and is called with <m>`
local function subprogram(f, pc, fn, name, params)
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
		for i = 1, #params do
			if compiled.params[i] ~= params[i] then
				refuse(f, pc, "'%s' is called with a %s and compiled with a %s", compiled.name,
					typenames[params[i]], typenames[compiled.params[i]])
			end
		end
		return compiled
	end
	local read = proto.read(fn)
	-- without this the prologue reads a register the call never set, and the verifier names it
	if read.numparams > #params then
		refuse(f, pc, "'%s' takes %d arguments and is called with %d", name or "a function",
			read.numparams, #params)
	end
	return compile(unit, fn, read, name, params, false)
end

---
-- Compiles one program: its function, and every function that function reaches.
-- @function luaebpf.emit.program
-- @tparam table program `{name, fn, default, drop, names, context}`
-- @treturn table the frames, the program's own first
-- @raise `a program takes one argument, the context`, and `<file>:<line>: <reason>` for every
--   construct the subset refuses
function emit.program(program)
	local unit = {
		functions = {}, order = {}, lowering = {}, names = program.names or {},
		default = program.default, drop = program.drop, context = program.context,
		-- no lowering can require luaebpf.emit back; read here, after the body that may set them ran
		maygoto = emit.maygoto, unaligned = emit.unaligned, subprogram = subprogram,
	}
	local read = proto.read(program.fn)
	if read.numparams > 1 then
		error(format("%s:%d: a program takes one argument, the context",
			(read.source:gsub("^@", "")), read.linedefined), 0)
	end
	compile(unit, program.fn, read, program.name, {CTX}, true)
	return unit.order
end

return emit

