--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- What every lowering shares: the declaration of a type a Lua register may hold, and the four
-- `resolve` gives, the words each frame reserves, the abstract state the walk carries along each
-- edge, where a Lua register lives, the loops whose iterator a jump out of them destroys, the
-- jumps, and the way out of a check that stops the program, which logs the error Lua raises there.
-- @module luaebpf.emit.frame

local insn  = require("luaebpf.insn")
local proto = require("luaebpf.proto")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local mathtype   = math.type

local NREGS    <const> = 4   -- Lua registers 0..3 live in r6..r9; the rest spill to the frame
local FIRST    <const> = reg.R6
local SLOT     <const> = 8
local NBITS    <const> = 64
local BYTE     <const> = 8   -- bits

-- the words every frame reserves: the flag a callee raises through the pointer its caller
-- passed, where the callee keeps that pointer, since R1-R5 do not survive a nested call, and
-- the key and the value a map helper is handed by address, the value also where a packet read
-- copies its bytes
local RESERVED <const> = 4
local ABORTED  <const> = -SLOT
local CALLER   <const> = -SLOT * 2
local KEY      <const> = -SLOT * 3
local VALUE    <const> = -SLOT * 4

local PAST     <const> = math.maxinteger -- where an abort jumps to: past every loop

-- the kfuncs of the kernel's open-coded iterator (kernel/bpf/bpf_iter.c), which counts the passes of
-- a loop whose bound the program computes, and which the kernel holds until the program destroys it
local iterator = {new = "bpf_iter_num_new", next = "bpf_iter_num_next", destroy = "bpf_iter_num_destroy"}

-- a stop's line goes to bpf_trace_printk as this format's argument: before v7.1 the helper prints
-- nothing for a format holding a byte past ASCII, which a file's path may (bpf_bprintf_prepare)
local FORMAT <const> = "%s\0"

-- the window a stop's line is rate limited in, two words of the object's .data, which its programs
-- share: a block names it first, so it heads .data, aligned for its words
local WINDOW <const> = ("\0"):rep(SLOT * 2)
local OPENED <const> = 0    -- the jiffies it opened at
local LOGGED <const> = SLOT -- the lines it logged since

local typenames = {}

-- the masks the frame's checks read, widened by each lowering that declares a type into one, so a
-- reader takes the field where it uses it and never copies it into a local
local classes = {
	word     = 0, -- a value the kernel holds as a word
	proxy    = 0, -- a pointer the kernel holds, or an offset into one, read through a proxy
	untested = 0, -- a word the program must test before the kernel reads it
}

local nextbit = 1

-- what a Lua register may hold, a bit each, declared by the lowering whose code first gives a
-- register that type, so a construct adds its own without editing a list every lowering shares
local function newtype(name, ...)
	local bit = nextbit
	nextbit = bit << 1
	typenames[bit] = name
	for _, class in ipairs({...}) do
		if classes[class] == nil then
			error(format("'%s' is not a class the frame reads", class), 2)
		end
		classes[class] = classes[class] | bit
	end
	return bit
end

local INT  <const> = newtype("number", "word")
local BOOL <const> = newtype("boolean", "word")
local NIL  <const> = newtype("nil", "word")

-- a value the compiler knows and the kernel never sees
local OTHER <const> = newtype("compile-time value")

local frame = {
	NREGS = NREGS, SLOT = SLOT, NBITS = NBITS, BYTE = BYTE, RESERVED = RESERVED, ABORTED = ABORTED,
	CALLER = CALLER, KEY = KEY, VALUE = VALUE, INT = INT, BOOL = BOOL, NIL = NIL, OTHER = OTHER,
	classes = classes, type = newtype, typenames = typenames, iterator = iterator,
}

-- a join reads as the type it holds first and what else it may be, nil last, so that a refusal never
-- names it as one type, e.g. "number that may be nil"
local function joinname(t)
	local mask = t & ~NIL
	local first = mask & -mask
	local others = {}
	mask = mask ~ first
	while mask ~= 0 do
		local bit = mask & -mask
		table.insert(others, "a " .. typenames[bit])
		mask = mask ~ bit
	end
	if t & NIL ~= 0 then
		table.insert(others, typenames[NIL])
	end
	return format("%s that may be %s", typenames[first], table.concat(others, " or "))
end

local function typename(value)
	if value == nil then
		return "undefined value"
	end
	if value.t == OTHER and value.k ~= nil then
		return type(value.k)
	end
	return typenames[value.t] or joinname(value.t)
end
frame.typename = typename

-- whether the type names one Lua type. A join widens a register to several, and the bits say
-- which for none of them: false, nil and the integer zero are one word.
local function exact(value)
	local mask = value ~= nil and value.t or 0
	return mask ~= 0 and (mask & (mask - 1)) == 0
end
frame.exact = exact

-- the chunk and the line a refusal names, and a stop logs, as Lua's own error spells them
local function where(f, pc)
	return format("%s:%d: ", f.chunk, f.proto.lines[pc] or f.proto.linedefined)
end

local function refuse(f, pc, reason, ...)
	error(where(f, pc) .. format(reason, ...), 0)
end
frame.refuse = refuse

-- the verifier of a kernel without efficient unaligned access refuses a read wider than a byte at
-- an offset it cannot prove aligned, and the compiler refuses every one there rather than prove
-- which it would take
local function aligned(f, pc, what, size)
	if size > 1 and not f.unit.unaligned then
		refuse(f, pc, "%s reads more than a byte, and this kernel lacks efficient unaligned access", what)
	end
end
frame.aligned = aligned

--- @section the abstract state

-- the join of two abstract values: the types of both, the compile-time value only where every
-- path agrees on it, the map a lookup came from where the other path agrees on it or is nil, and the
-- codec a view reads with where every path agrees on it
local function join(a, b)
	if a == nil or b == nil then
		return a or b
	end
	if a.t == b.t and a.k == b.k and a.map == b.map and a.codec == b.codec then
		return a
	end
	local map = a.map == b.map and a.map or a.t == NIL and b.map or b.t == NIL and a.map or nil
	return {t = a.t | b.t, k = a.k == b.k and a.k or nil, name = a.name == b.name and a.name or nil,
		map = map, codec = a.codec == b.codec and a.codec or nil}
end

local function same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.t == b.t and a.k == b.k and a.map == b.map and a.codec == b.codec
end

local function copy(state)
	local out = {}
	for i, value in pairs(state) do
		out[i] = value
	end
	return out
end
frame.copy = copy

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
frame.reach = reach

--- @section Lua registers

local function spilled(i)
	return i >= NREGS
end

local function offset(i)
	return -SLOT * (i - NREGS + 1 + RESERVED)
end

-- the bytes a frame holds: the words it reserves, the Lua registers that spill below them, and the
-- iterator of each loop the code being emitted is in
local function depth(f)
	return (math.max(f.proto.maxstacksize - NREGS, 0) + RESERVED + #f.loops) * SLOT
end
frame.depth = depth

-- a frame deeper than eBPF allows is refused at the line that needs it
local function stack(f, pc, bytes)
	local limit = f.unit.maxstack
	if bytes > limit then
		refuse(f, pc, "the function needs %d bytes of stack, over the %d eBPF allows", bytes, limit)
	end
end
frame.stack = stack

-- the word a Lua register holds, whatever its type
local function fetch(f, i, scratch)
	if spilled(i) then
		f.code:load(scratch, reg.FP, offset(i))
		return scratch
	end
	return FIRST + i
end
frame.fetch = fetch

-- the value's name quoted, or what the caller says of one with none
local function named(value, otherwise)
	return value.name and format("'%s'", value.name) or otherwise
end
frame.named = named

-- the verifier lets a lookup's pointer be used only where the program has tested it
local function tested(f, pc, value)
	if value ~= nil and (value.t & classes.untested) ~= 0 then
		refuse(f, pc, "%s may be nil here; test it first", named(value, "a value"))
	end
end
frame.tested = tested

local function getreg(f, pc, state, i, scratch)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	tested(f, pc, value)
	if mask == 0 or (mask & ~classes.word) ~= 0 then
		refuse(f, pc, "a %s has no value in the kernel here", typename(value))
	end
	return fetch(f, i, scratch)
end
frame.getreg = getreg

local function setreg(f, i, src)
	if spilled(i) then
		f.code:store(reg.FP, offset(i), src)
	else
		f.code:alu(alu.MOV, FIRST + i, src)
	end
end
frame.setreg = setreg

local function setimm(f, i, value)
	if spilled(i) then
		f.code:set(reg.R1, value)
		f.code:store(reg.FP, offset(i), reg.R1)
	else
		f.code:set(FIRST + i, value)
	end
end
frame.setimm = setimm

-- dst := the address of the frame's bytes at `at`, which a call reads through a pointer
local function address(f, dst, at)
	f.code:alu(alu.MOV, dst, reg.FP)
	f.code:alui(alu.ADD, dst, at)
end
frame.address = address

local function move(f, from, scratch)
	if from ~= scratch then
		f.code:alu(alu.MOV, scratch, from)
	end
	return scratch
end
frame.move = move

-- reads a Lua register into a scratch register the caller may then destroy
local function into(f, pc, state, i, scratch)
	return move(f, getreg(f, pc, state, i, scratch), scratch)
end
frame.into = into

local function isinteger(value)
	return value ~= nil and value.t == INT
end
frame.isinteger = isinteger

-- a value the file body computed becomes a constant of the program; only what the kernel can
-- hold takes a register, and a float, which the body's Lua has and the kernel's does not, is not one
local function resolve(f, pc, state, i, value, name)
	local kind = mathtype(value) or type(value)
	if kind == "integer" then
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
frame.resolve = resolve

local function constant(f, pc, i)
	if i >= f.proto.nk then
		refuse(f, pc, "constant #%d does not exist", i + 1)
	end
	return f.proto.k[i + 1]
end
frame.constant = constant

-- a shift pair rather than BPF_MEMSX, which the s390 JIT of v6.6 does not take
local function extend(f, dst, size)
	local shift = NBITS - size * BYTE
	f.code:alui(alu.LSH, dst, shift)
	f.code:alui(alu.ARSH, dst, shift)
end
frame.extend = extend

-- as lib/struct.lua's codec reads a bitfield, so that a compiled read and an interpreted one agree
local function bitfield(f, dst, field)
	local code = f.code
	if field.shift ~= 0 then
		code:alui(alu.RSH, dst, field.shift)
	end
	code:set(reg.R5, field.mask) -- an immediate is 32 bits sign-extended, which a mask may not fit
	code:alu(alu.AND, dst, reg.R5)
	if field.signed then
		code:set(reg.R5, (field.mask >> 1) + 1) -- the sign bit's weight: xor, then subtract, sign-extends

		code:alu(alu.XOR, dst, reg.R5)
		code:alu(alu.SUB, dst, reg.R5)
	end
end

-- a field that is no bitfield, out of its load in dst: swapped where the layout marks it bigendian, a
-- byte having no order and BPF_END taking 2, 4 or 8 of them, and its sign extended where it is signed
local function whole(f, dst, field)
	if field.bigendian and field.size > 1 then
		f.code:swap(dst, field.size)
	end
	if field.signed and field.size * BYTE < NBITS then
		extend(f, dst, field.size)
	end
end

-- Lua register a := the number a codec reads out of a field's load in R1, named name
local function decode(f, state, a, field, name)
	if field.mask ~= nil then
		bitfield(f, reg.R1, field)
	else
		whole(f, reg.R1, field)
	end
	setreg(f, a, reg.R1)
	state[a] = {t = INT, name = name}
end
frame.decode = decode

--- @section loops

-- R1 := the address of the loop's iterator, which every kfunc of the iterator takes first
local function iterate(f, kfunc, loop)
	address(f, reg.R1, loop.slot)
	f.code:kfunc(kfunc)
end
frame.iterate = iterate

-- the loop of the FORPREP at pc and the FORLOOP at last, whose iterator takes the word below every
-- other the frame holds while the code between them is emitted
local function enter(f, pc, last)
	local loop = {first = pc, last = last, line = f.proto.lines[pc], exits = {}}
	table.insert(f.entered, loop)
	table.insert(f.loops, loop)
	loop.slot = -depth(f)
	stack(f, pc, depth(f))
	return loop
end
frame.enter = enter

-- the loops the code at pc is in, outermost first
local function within(f, pc)
	local loops = {}
	for _, loop in ipairs(f.entered) do
		if loop.first < pc and pc <= loop.last then
			table.insert(loops, loop)
		end
	end
	f.loops = loops
end
frame.within = within

-- a return leaves every loop: what it emits after the destroys is in none
local function leave(f)
	for i = #f.loops, 1, -1 do
		iterate(f, iterator.destroy, f.loops[i])
	end
	f.loops = {}
end
frame.leave = leave

-- the label a jump to target takes from the loop at level and those around it: a target past its
-- FORLOOP leaves the loop, through the destroy of its iterator, which every jump to that target shares
local function route(f, level, target, label)
	local loop = f.loops[level]
	if loop == nil or target <= loop.last then
		return label
	end
	local exit = loop.exits[target]
	if exit == nil then
		exit = {label = f.code:label(), loop = loop, to = route(f, level - 1, target, label)}
		loop.exits[target] = exit
		table.insert(f.exits, exit)
	end
	return exit.label
end

-- the destroys a jump out of a loop goes through, each on to the next loop out or to its target
local function exits(f)
	for _, exit in ipairs(f.exits) do
		f.code:source(exit.loop.line)
		f.code:place(exit.label)
		iterate(f, iterator.destroy, exit.loop)
		f.code:jump(exit.to)
	end
end
frame.exits = exits

--- @section control flow

local function labelof(f, pc)
	local label = f.labels[pc]
	if label == nil then
		refuse(f, pc, "a jump leaves the function")
	end
	return route(f, #f.loops, pc, label)
end
frame.labelof = labelof

-- the tail taken where the interpreter would raise: the error verdict of the program's type in its
-- own frame, and the flag that carries the stop one frame up everywhere else
local function abort(f)
	if f.aborted == nil then
		f.aborted = f.code:label()
	end
	return route(f, #f.loops, PAST, f.aborted)
end
frame.abort = abort

-- the way out of a check where Lua would raise: a block of its own, which logs the error Lua raises
-- there, `<chunk>:<line>: <reason>`, and then takes the tail abort gives the loops the check is in
local function stop(f, pc, reason, ...)
	local site = {label = f.code:label(), line = f.proto.lines[pc], after = abort(f),
		message = where(f, pc) .. format(reason, ...) .. "\0"}
	table.insert(f.stops, site)
	return site.label
end
frame.stop = stop

-- R1 := the window, opened again where more than DEFAULT_RATELIMIT_INTERVAL jiffies passed since it
-- opened, as ___ratelimit opens its own, and the jump to `spent` where it logged its burst already
local function window(f, func, limit, spent)
	local code, counted = f.code, f.code:label()
	code:helper(func.jiffies64)
	code:data(reg.R1, WINDOW)
	code:load(reg.R2, reg.R1, OPENED)
	code:alu(alu.MOV, reg.R3, reg.R0)
	code:alu(alu.SUB, reg.R3, reg.R2)
	code:branchi(jump.JLE, reg.R3, limit.INTERVAL, counted)
	code:store(reg.R1, OPENED, reg.R0)
	code:storei(reg.R1, LOGGED, 0)
	code:place(counted)
	code:load(reg.R2, reg.R1, LOGGED)
	code:branchi(jump.JGE, reg.R2, limit.BURST, spent)
	code:alui(alu.ADD, reg.R2, 1)
	code:store(reg.R1, LOGGED, reg.R2)
end

-- each stop's block, after the function's tail: its line to the trace ring under the kernel's
-- default rate limit, as luakfunc_err logs a callback's error, since bpf_trace_printk limits nothing
local function stops(f)
	if #f.stops == 0 then
		return
	end
	local code = f.code
	local func, limit = proto.script("linux.bpf").func, proto.script("linux.ratelimit").default
	for _, site in ipairs(f.stops) do
		code:source(site.line)
		code:place(site.label)
		window(f, func, limit, site.after)
		code:data(reg.R1, FORMAT)
		code:set(reg.R2, #FORMAT)
		code:data(reg.R3, site.message)
		code:helper(func.trace_printk)
		code:jump(site.after)
	end
end
frame.stops = stops

-- a value the program computes past `size` unsigned bytes, fewer than a register holds, stops
-- the program where Lua raises `reason`
local function fitsunsigned(f, pc, src, size, reason)
	local code = f.code
	code:alu(alu.MOV, reg.R5, src)
	code:alui(alu.RSH, reg.R5, size * BYTE)
	code:branchi(jump.JNE, reg.R5, 0, stop(f, pc, reason))
end
frame.fitsunsigned = fitsunsigned

local function jumptarget(f, pc)
	local ins = f.proto.code[pc]
	if ins == nil or ins.op ~= opcodes.JMP then
		refuse(f, pc - 1, "a test is not followed by a jump")
	end
	local target = pc + ins.sj + 1
	if target <= pc then
		refuse(f, pc, "'while', 'repeat' and a 'goto' backwards are not compiled yet")
	end
	return target
end
frame.jumptarget = jumptarget

-- the test of a word the kernel answered against `word`, its nil: `found` narrows the register on the
-- arm that found another, the other arm holds nil's zero word, and `taken` is whether the opcode's
-- jump is the former
local function narrow(f, pc, ins, state, word, taken, found)
	local code, value = f.code, state[ins.a]
	local target = jumptarget(f, pc + 1)
	local hit = taken and target or pc + 2
	local miss = taken and pc + 2 or target
	local absent = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), word, absent)
	local narrowed = copy(state)
	found(f, pc, narrowed, ins.a, value)
	code:jump(labelof(f, hit))
	reach(f, hit, narrowed)
	code:place(absent)
	if word ~= 0 then
		setimm(f, ins.a, 0)
	end
	code:jump(labelof(f, miss))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, miss, state)
	return false
end
frame.narrow = narrow

return frame

