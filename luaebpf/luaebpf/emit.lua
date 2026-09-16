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

local insn     = require("luaebpf.insn")
local maps     = require("luaebpf.maps")
local proto    = require("luaebpf.proto")
local runtimes = require("luaebpf.runtimes")
local vmlinux  = require("luaebpf.vmlinux")

local alu, jump, reg = insn.alu, insn.jump, insn.reg
local opcodes    = proto.opcodes
local format     = string.format
local unpack     = string.unpack
local insert     = table.insert
local max        = math.max
local getinfo    = debug.getinfo
local getupvalue = debug.getupvalue

local NREGS    <const> = 4   -- Lua registers 0..3 live in r6..r9; the rest spill to the frame
local FIRST    <const> = reg.R6
local SLOT     <const> = 8
local MAXSTACK <const> = 512 -- MAX_BPF_STACK
local MAXARGS  <const> = 4   -- MAX_BPF_FUNC_REG_ARGS, less the register the abort pointer takes
local NBITS    <const> = 64
local BYTE     <const> = 8   -- bits
local ROUNDS   <const> = 16
local NAMELEN  <const> = 15  -- BPF_OBJ_NAME_LEN - 1
local MININT   <const> = 1 << 63

-- the program's context is its own parameter, Lua register 0
local CTXREG <const> = 0

-- what the kfunc the escape hatch calls does: answers an int, with -1 where Lua would answer
-- nil, and NUL-terminates the key it was handed in place (lunatik_ebpf.h)
local ANSWERSIZE <const> = 4
local NORUNTIME  <const> = -1
local KEYNUL     <const> = 1

-- the words every frame reserves: the flag a callee raises through the pointer its caller
-- passed, where the callee keeps that pointer, since R1-R5 do not survive a nested call, and
-- the key and the value a map helper is handed by address
local RESERVED <const> = 4
local ABORTED  <const> = -SLOT
local CALLER   <const> = -SLOT * 2
local KEY      <const> = -SLOT * 3
local VALUE    <const> = -SLOT * 4

-- what a Lua register may hold; OTHER is a value the compiler knows and the kernel never sees
local INT     <const> = 1
local BOOL    <const> = 2
local NIL     <const> = 4
local CTX     <const> = 8
local OTHER   <const> = 16
local PACKET  <const> = 32
local METHOD  <const> = 64
local MAYBE   <const> = 128              -- a map value the program has not tested yet
local RECORD  <const> = 256              -- a struct map value, read a field at a time
local ANSWER  <const> = 512              -- what a call into the kernel runtime answered
local BUFFER  <const> = 1024             -- packet bytes a getstring read into the frame
local RUNTIME  <const> = INT | BOOL | NIL | ANSWER -- a value the kernel holds as a word
local PROXY    <const> = CTX | PACKET | MAYBE | RECORD -- a pointer the kernel holds, read through a proxy
local UNTESTED <const> = MAYBE | ANSWER -- a word the program must test before the kernel reads it
local CARRIED  <const> = RUNTIME | PROXY | BUFFER -- what a Lua register holds a word of its own for

local typenames = {[INT] = "number", [BOOL] = "boolean", [NIL] = "nil", [CTX] = "context",
	[PACKET] = "packet", [METHOD] = "method", [MAYBE] = "map value",
	[RECORD] = "struct map value", [ANSWER] = "runtime answer", [BUFFER] = "string"}

local opnames = {}
for name, op in pairs(opcodes) do
	opnames[op] = name
end

local emit = {}

-- the compiler runs on the machine that loads what it emits, so the kernel it reads is the one
-- it compiles for; the name is what a refusal quotes back
local function release()
	local f = io.open("/proc/sys/kernel/osrelease", "r")
	if f == nil then
		return "unknown"
	end
	local line = f:read("l")
	f:close()
	return line or "unknown"
end

local kernel = release()
local major, minor = kernel:match("^(%d+)%.(%d+)")
major, minor = tonumber(major) or 0, tonumber(minor) or 0

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

--- @section what the kernel offers

-- What the compiler may lower here. The compiler runs on the machine that loads what it emits,
-- so it asks the kernel rather than reading a release; LUAEBPF_PROBE replaces the answer, which
-- is what exercises every lowering and every refusal on one host.
local probes = {}

-- a helper and a kfunc are both a FUNC in the kernel's own BTF, and the helper a getstring takes
-- is the program type's
function probes.loadbytes(f)
	return vmlinux.publishes(f.unit.context.loadbytes.probe)
end

local function offers(f, feature)
	local unit = f.unit
	if unit.allowed ~= nil then
		return unit.allowed[feature] == true
	end
	local answer = unit.offers[feature]
	if answer == nil then
		answer = probes[feature](f)
		unit.offers[feature] = answer
	end
	return answer
end

-- a value the verifier only lets the kernel read where the program found it good: a map lookup's
-- pointer, narrowed at the test, and the sentinel a call into the runtime answers
local function tested(f, pc, a, b)
	local value = (a ~= nil and (a.t & UNTESTED) ~= 0 and a) or (b ~= nil and (b.t & UNTESTED) ~= 0 and b)
	if value then
		refuse(f, pc, "'%s' may be nil here; test it first", value.name or "a value")
	end
end

--- @section the abstract state

-- the join of two abstract values: the types of both, and what the compiler holds itself only
-- where every path agrees on it: the value, the map a lookup came from, the upper bound a
-- comparison proved, and the frame buffer a string was read into
local function join(a, b)
	if a == nil or b == nil then
		return a or b
	end
	if a.t == b.t and a.k == b.k and a.map == b.map and a.bound == b.bound and a.at == b.at then
		return a
	end
	return {t = a.t | b.t, k = a.k == b.k and a.k or nil, name = a.name == b.name and a.name or nil,
		map = a.map == b.map and a.map or nil, bound = a.bound == b.bound and a.bound or nil,
		at = a.at == b.at and a.at or nil}
end

local function same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.t == b.t and a.k == b.k and a.map == b.map and a.bound == b.bound and a.at == b.at
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

local function grow(f, pc, bytes)
	if bytes > MAXSTACK then
		refuse(f, pc, "the function needs %d bytes of stack, over the %d eBPF allows", bytes, MAXSTACK)
	end
	f.stack = bytes
end

-- the words below the frame one call site owns, for what an address is taken of: the arguments
-- a kfunc is handed, and the bytes a getstring reads. One region per site, so a re-walk finds
-- the same offset; a .data section would become a libbpf map whose name carries a dot, which
-- bpffs refuses as a pin.
local function region(f, pc, words)
	local at = f.regions[pc]
	if at == nil then
		grow(f, pc, f.stack + words * SLOT)
		at = -f.stack
		f.regions[pc] = at
	end
	return at
end

-- the word a Lua register holds, whatever its type
local function fetch(f, i, scratch)
	if spilled(i) then
		f.code:load(scratch, reg.FP, offset(i))
		return scratch
	end
	return FIRST + i
end

local function getreg(f, pc, state, i, scratch)
	local value = state[i]
	local mask = value ~= nil and value.t or 0
	tested(f, pc, value)
	if mask == 0 or (mask & ~RUNTIME) ~= 0 then
		refuse(f, pc, "a %s has no value in the kernel here", typename(value))
	end
	return fetch(f, i, scratch)
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

local function move(f, from, scratch)
	if from ~= scratch then
		f.code:alu(alu.MOV, scratch, from)
	end
	return scratch
end

-- reads a Lua register into a scratch register the caller may then destroy
local function into(f, pc, state, i, scratch)
	return move(f, getreg(f, pc, state, i, scratch), scratch)
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

-- the jump is taken where the relation holds as the opcode's k says, so each arm carries what
-- the comparison proved on it
local function testjump(f, pc, state, op, dst, src, taken, fallen)
	local target = jumptarget(f, pc + 1)
	f.code:branch(op, dst, src, labelof(f, target))
	reach(f, target, taken or state)
	reach(f, pc + 2, fallen or state)
	return false
end

--- @section the context

-- the running kernel's own layout of the context struct, read once per program
local function layout(f)
	local unit = f.unit
	if unit.layout == nil then
		unit.layout = {}
		for _, field in ipairs(vmlinux.layout(unit.context.struct).fields) do
			unit.layout[field.name] = field
		end
	end
	return unit.layout
end

-- what a name reads on the context, refused where the kernel's own rules say a program may not
local function contextfield(f, pc, key, writing)
	local context = f.unit.context
	if key == context.packet.base or key == context.packet.limit then
		refuse(f, pc, "'%s' is a packet bound, not a number; '#' on the packet is its length", key)
	end
	local field = context.fields[key] and layout(f)[key]
	if field == nil then
		refuse(f, pc, "the context has no field '%s'", key)
	end
	if writing and not context.writable[key] then
		refuse(f, pc, "the context field '%s' cannot be written", key)
	end
	return field
end

-- every field a context proxy exposes is an unsigned word, so the load needs no extension
local function contextget(f, pc, ins, state, key)
	local field = contextfield(f, pc, key, false)
	f.code:load(reg.R2, fetch(f, ins.b, reg.R1), field.offset, field.size)
	setreg(f, ins.a, reg.R2)
	state[ins.a] = {t = INT, name = key}
end

local function contextset(f, pc, ins, state, key)
	local field = contextfield(f, pc, key, true)
	local src = reg.R2
	if ins.k then
		local value = constant(f, pc, ins.c)
		if type(value) ~= "number" then
			refuse(f, pc, "the context field '%s' takes a number, not a %s", key, type(value))
		end
		f.code:set(src, value)
	else
		if not isinteger(state[ins.c]) then
			refuse(f, pc, "the context field '%s' takes a number, not a %s", key,
				typename(state[ins.c]))
		end
		src = getreg(f, pc, state, ins.c, src)
	end
	f.code:store(fetch(f, ins.a, reg.R1), field.offset, src, field.size)
end

--- @section the packet

-- MAX_PACKET_OFF: the verifier refuses arithmetic between a packet pointer and a register whose
-- range it does not know, and find_good_pkt_pointers leaves a pointer no range at all once the
-- offset's maximum plus the access would carry it past this. So an access tests its offset
-- against the last one its width can start at. Anything above is out of bounds on every packet
-- BPF_PROG_TEST_RUN or a NIC can build, and the interpreter raises there too.
local PACKETMAX <const> = 65535

-- the reads the kernel's own data object publishes (lib/luadata.c), and the load each becomes.
-- There is no getuint64: a Lua integer is 64-bit signed and has no unsigned twin.
local accessors = {
	getbyte   = {size = 1, signed = false},
	getuint8  = {size = 1, signed = false},
	getint8   = {size = 1, signed = true},
	getuint16 = {size = 2, signed = false},
	getint16  = {size = 2, signed = true},
	getuint32 = {size = 4, signed = false},
	getint32  = {size = 4, signed = true},
	getint64  = {size = 8, signed = true},
	getnumber = {size = 8, signed = true},
}

-- an accessor is called with the receiver and the offset, both of which OP_CALL counts, and
-- getstring with a length besides
local ACCESSARGS <const> = 2
local STRINGARGS <const> = 3

-- the read that answers bytes rather than a number, and the frame buffer it reads into: eight
-- words of the 512 a frame has, which is what a c64 map key takes
local STRING    <const> = "getstring"
local STRINGMAX <const> = 64

-- data and data_end, which the kernel rewrites a four-byte context load of into a full pointer
local function bounds(f)
	local packet, fields = f.unit.context.packet, layout(f)
	return fields[packet.base], fields[packet.limit]
end

-- BPF_MEMSX landed in v6.6 and the tree supports 5.15, so a signed read extends by hand
local function extend(f, dst, size)
	local shift = NBITS - size * BYTE
	f.code:alui(alu.LSH, dst, shift)
	f.code:alui(alu.ARSH, dst, shift)
end

-- One access, self-contained: data and data_end are re-read from the context rather than kept
-- live, so the proxy is one register that survives a call and cannot go stale.
local function packetread(f, pc, ins, state, access)
	local code, base, limit = f.code, bounds(f)
	into(f, pc, state, ins.a + 2, reg.R4)
	local ptr = fetch(f, ins.a + 1, reg.R3)
	code:load(reg.R1, ptr, base.offset, base.size)
	code:load(reg.R2, ptr, limit.offset, limit.size)
	code:branchi(jump.JGT, reg.R4, PACKETMAX - access.size, abort(f))
	code:alu(alu.ADD, reg.R1, reg.R4)
	if f.drop ~= "bounds" then
		code:alu(alu.MOV, reg.R4, reg.R1)
		code:alui(alu.ADD, reg.R4, access.size)
		code:branch(jump.JGT, reg.R4, reg.R2, abort(f))
	end
	code:load(reg.R1, reg.R1, 0, access.size)
	if access.signed and access.size * BYTE < NBITS then
		extend(f, reg.R1, access.size)
	end
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT}
end

-- the length is the distance between the bounds, which is what '#' on the kernel's data object
-- answers and what the interpreted twin reads off the same bytes
local function packetlen(f, ins, state)
	local code, base, limit = f.code, bounds(f)
	local ptr = fetch(f, ins.b, reg.R3)
	code:load(reg.R1, ptr, base.offset, base.size)
	code:load(reg.R2, ptr, limit.offset, limit.size)
	code:alu(alu.SUB, reg.R2, reg.R1)
	setreg(f, ins.a, reg.R2)
	state[ins.a] = {t = INT}
end

-- the helper that copies packet bytes into the frame, which is the program type's; only one of
-- them is younger than the kernels the tree supports, and only that one is probed for
local function loadbytes(f, pc)
	local helper = f.unit.context.loadbytes
	if helper.probe ~= nil and not offers(f, "loadbytes") then
		refuse(f, pc, "'%s' needs %s, which this kernel (%s) lacks", STRING, helper.probe, kernel)
	end
	return helper.number
end

-- The bytes a program reads out of the packet, into a buffer of its frame: the compiler holds
-- the buffer's offset and the Lua register carries what was read into it, so a comparison knows
-- both. The helper is handed a length the program proved against a constant, since the verifier
-- refuses one whose maximum it cannot see, and a buffer zeroed first, since with a length that
-- is not a constant it requires the memory it could fill to be initialized.
local function packetstring(f, pc, ins, state)
	local code, words = f.code, STRINGMAX // SLOT
	if ins.b - 1 < STRINGARGS then
		refuse(f, pc, "'%s' takes an offset and a length", STRING)
	end
	local at, length = state[ins.a + 2], state[ins.a + 3]
	if not isinteger(at) or not isinteger(length) then
		refuse(f, pc, "'%s' takes numbers, not a %s and a %s", STRING, typename(at), typename(length))
	end
	local bound = length.k or length.bound
	if bound == nil then
		refuse(f, pc, "'%s' needs a length the program tested against a constant", STRING)
	end
	if bound > STRINGMAX then
		refuse(f, pc, "'%s' reads at most %d bytes, and this length is bounded at %d",
			STRING, STRINGMAX, bound)
	end
	local helper = loadbytes(f, pc)
	local buffer = region(f, pc, words)
	into(f, pc, state, ins.a + 2, reg.R2)
	into(f, pc, state, ins.a + 3, reg.R4)
	-- luadata_checkbounds raises below one byte, and ARG_CONST_SIZE refuses a zero-sized read
	code:branchi(jump.JSLT, reg.R4, 1, abort(f))
	code:branchi(jump.JGT, reg.R2, PACKETMAX - bound, abort(f))
	for i = 0, words - 1 do
		code:storei(reg.FP, buffer + i * SLOT, 0)
	end
	setreg(f, ins.a, reg.R4) -- the length is the value of the read, and R1-R5 do not survive the call
	move(f, fetch(f, ins.a + 1, reg.R1), reg.R1)
	code:alu(alu.MOV, reg.R3, reg.FP)
	code:alui(alu.ADD, reg.R3, buffer)
	code:helper(helper)
	code:branchi(jump.JNE, reg.R0, 0, abort(f))
	state[ins.a] = {t = BUFFER, at = buffer, bound = bound}
end

-- the packet proxy is the context register under another type: one register, passed to a
-- subprogram in one argument, with nothing to keep live across a call
local function contextmethod(f, pc, ins, state, callee)
	if callee.name ~= "packet" then
		refuse(f, pc, "the context has no method '%s'", callee.name)
	end
	setreg(f, ins.a, fetch(f, ins.a + 1, reg.R1))
	state[ins.a] = {t = PACKET, name = callee.name}
end

local function method(f, pc, ins, state, callee)
	local recv = callee.recv
	if recv.t == CTX then
		return contextmethod(f, pc, ins, state, callee)
	end
	if recv.t == PACKET and callee.name == STRING then
		return packetstring(f, pc, ins, state)
	end
	local access = recv.t == PACKET and accessors[callee.name]
	if not access then
		refuse(f, pc, "the %s has no method '%s'", typename(recv), callee.name)
	end
	-- getreg takes any word, so an unchecked offset reads where the interpreter would raise
	if ins.b - 1 < ACCESSARGS then
		refuse(f, pc, "'%s' takes an offset", callee.name)
	end
	local at = state[ins.a + 2]
	if not isinteger(at) then
		refuse(f, pc, "'%s' takes a number, not a %s", callee.name, typename(at))
	end
	packetread(f, pc, ins, state, access)
end

--- @section maps

local LOOKUP <const> = 1 -- BPF_FUNC_map_lookup_elem
local UPDATE <const> = 2 -- BPF_FUNC_map_update_elem
local DELETE <const> = 3 -- BPF_FUNC_map_delete_elem
local ANY    <const> = 0 -- BPF_ANY, the flags an unconditional update takes

-- a map holds what its spec packs, and this phase packs numbers
local function mapnumber(f, pc, what)
	refuse(f, pc, "a map %s is a number here", what)
end

-- a helper takes the key and the value by address, so each goes to the slot its frame reserves,
-- zeroed first because one narrower than a word leaves the rest of the slot to what was there
local function mapslot(f, at, src, size)
	f.code:storei(reg.FP, at, 0)
	f.code:store(reg.FP, at, src, size)
end

-- the map in R1 and the key's address in R2, where every map helper wants them. Lua registers
-- live in R6-R9 and the frame, so the call clobbers nothing live.
local function maphelper(f, map)
	local code = f.code
	code:map(reg.R1, map.name)
	code:alu(alu.MOV, reg.R2, reg.FP)
	code:alui(alu.ADD, reg.R2, KEY)
end

local function maplookup(f, ins, state, map, key)
	mapslot(f, KEY, key, map.key.size)
	maphelper(f, map)
	f.code:helper(LOOKUP)
	setreg(f, ins.a, reg.R0)
	state[ins.a] = {t = MAYBE, map = map, name = map.name}
end

local function mapread(f, pc, ins, state, map)
	if not isinteger(state[ins.c]) then
		mapnumber(f, pc, "key")
	end
	maplookup(f, ins, state, map, getreg(f, pc, state, ins.c, reg.R3))
end

-- the value a store writes, or nil for the assignment that deletes the entry
local function stored(f, pc, ins, state)
	if ins.k then
		local held = constant(f, pc, ins.c)
		if held == nil then
			return nil
		end
		if type(held) ~= "number" then
			mapnumber(f, pc, "value")
		end
		f.code:set(reg.R4, held)
		return reg.R4
	end
	local held = state[ins.c]
	if held ~= nil and held.t == NIL then
		return nil
	end
	if not isinteger(held) then
		mapnumber(f, pc, "value")
	end
	return getreg(f, pc, state, ins.c, reg.R4)
end

local function mapstore(f, pc, ins, state, map, key)
	local code = f.code
	if map.value.fields ~= nil then
		refuse(f, pc, "a struct map value is read-only in a compiled function")
	end
	local value = stored(f, pc, ins, state)
	mapslot(f, KEY, key, map.key.size)
	if value == nil then
		maphelper(f, map)
		code:helper(DELETE)
		return
	end
	mapslot(f, VALUE, value, map.value.size)
	maphelper(f, map)
	code:alu(alu.MOV, reg.R3, reg.FP)
	code:alui(alu.ADD, reg.R3, VALUE)
	code:set(reg.R4, ANY)
	code:helper(UPDATE)
end

-- the map a lookup came from, or the refusal for a register two lookups merged into: a join
-- drops what the paths disagree on, and which map a value is read with is one of those
local function mapfrom(f, pc, value)
	if value.map == nil then
		refuse(f, pc, "a map value here comes from more than one map")
	end
	return value.map
end

-- one field of a struct value, at the offset and the width its codec carries
local function mapfield(f, pc, ins, state, value, key)
	local field = mapfrom(f, pc, value).value.fields[key]
	if field == nil then
		refuse(f, pc, "a map value has no field '%s'", key)
	end
	f.code:load(reg.R1, fetch(f, ins.b, reg.R1), field.offset, field.size)
	if field.signed and field.size * BYTE < NBITS then
		extend(f, reg.R1, field.size)
	end
	setreg(f, ins.a, reg.R1)
	state[ins.a] = {t = INT, name = key}
end

-- the map a write names, or the refusal for a table that is not one
local function mapof(f, pc, state, i)
	local container = state[i]
	if container == nil or not maps.declares(container.k) then
		refuse(f, pc, "a table cannot be written in a compiled function")
	end
	return container.k
end

-- the value behind a pointer the program has just found non-null, which is the only place the
-- verifier lets it be read. A struct stays the pointer it is, and its fields are read one at a
-- time from there.
local function mapvalue(f, pc, state, i, value)
	local map = mapfrom(f, pc, value)
	local spec = map.value
	if spec.fields ~= nil then
		state[i] = {t = RECORD, map = map, name = value.name}
		return
	end
	f.code:load(reg.R1, fetch(f, i, reg.R1), 0, spec.size)
	if spec.signed and spec.size * BYTE < NBITS then
		extend(f, reg.R1, spec.size)
	end
	setreg(f, i, reg.R1)
	state[i] = {t = INT, name = value.name}
end

-- a lookup is narrowed where the program tests it, and the read goes on the branch that found
-- it good: the verifier refuses it anywhere else, and the other branch carries a nil
local function testlookup(f, pc, ins, state)
	local code, value = f.code, state[ins.a]
	local target = jumptarget(f, pc + 1)
	local truthy = ins.k and target or pc + 2
	local falsy = ins.k and pc + 2 or target
	local null = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), 0, null)
	local taken = copy(state)
	mapvalue(f, pc, taken, ins.a, value)
	code:jump(labelof(f, truthy))
	reach(f, truthy, taken)
	code:place(null)
	code:jump(labelof(f, falsy))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, falsy, state)
	return false
end

--- @section the kernel runtime

-- Lua's nil is the only false value the kfunc can answer, so 'if v then' and 'v == nil' are the
-- same test against the -1 it answers; whennil says which arm the opcode's jump is
local function testanswer(f, pc, ins, state, whennil)
	local code, value = f.code, state[ins.a]
	local target = jumptarget(f, pc + 1)
	local number = whennil and pc + 2 or target
	local absent = whennil and target or pc + 2
	local missing = code:label()
	code:branchi(jump.JEQ, fetch(f, ins.a, reg.R1), NORUNTIME, missing)
	local taken = copy(state)
	taken[ins.a] = {t = INT, name = value.name}
	code:jump(labelof(f, number))
	reach(f, number, taken)
	code:place(missing)
	setimm(f, ins.a, 0) -- the register still carries the sentinel, and the emitter's nil is a zero word
	code:jump(labelof(f, absent))
	state[ins.a] = {t = NIL, name = value.name}
	reach(f, absent, state)
	return false
end

-- the escape hatch: the runtime key and every argument in the frame, the program's context in
-- R3, and the int the kfunc answers sign-extended into the word the program then tests
local function runtimecall(f, pc, ins, state, callee)
	local code, nargs, ctx = f.code, ins.b - 1, state[CTXREG]
	if not f.isprogram then
		refuse(f, pc, "'%s' can only be called from the program's own function",
			callee.name or "a runtime")
	end
	if ctx == nil or ctx.t ~= CTX then
		refuse(f, pc, "a call into the runtime takes the context, which this program does not")
	end
	for i = 1, nargs do
		if not isinteger(state[ins.a + i]) then
			refuse(f, pc, "argument #%d is a %s, and a call into the runtime passes numbers",
				i, typename(state[ins.a + i]))
		end
	end
	local key = callee.k.key
	-- the kfunc NUL-terminates the key in place, so the buffer holds one byte more than the name
	local words = (#key + KEYNUL + SLOT - 1) // SLOT
	local at = region(f, pc, words + nargs)
	local args = at + words * SLOT
	-- the store is in the host's byte order, so each word is read out of the key in that order
	local padded = key .. ("\0"):rep(words * SLOT - #key)
	for i = 1, words do
		code:set(reg.R1, unpack("=i8", padded, (i - 1) * SLOT + 1))
		code:store(reg.FP, at + (i - 1) * SLOT, reg.R1)
	end
	for i = 1, nargs do
		code:store(reg.FP, args + (i - 1) * SLOT, getreg(f, pc, state, ins.a + i, reg.R1))
	end
	move(f, fetch(f, CTXREG, reg.R3), reg.R3)
	code:alu(alu.MOV, reg.R1, reg.FP)
	code:alui(alu.ADD, reg.R1, at)
	code:set(reg.R2, #key + KEYNUL)
	if nargs == 0 then
		code:set(reg.R4, 0) -- the verifier takes a null pointer where the size is zero
	else
		code:alu(alu.MOV, reg.R4, reg.FP)
		code:alui(alu.ADD, reg.R4, args)
	end
	code:set(reg.R5, nargs * SLOT)
	code:kfunc(f.unit.kfunc)
	insert(f.calls, {chunk = f.chunk, line = f.proto.lines[pc], key = key})
	extend(f, reg.R0, ANSWERSIZE)
	if ins.c > 1 then
		setreg(f, ins.a, reg.R0)
		state[ins.a] = {t = ANSWER, name = callee.name}
	end
end

--- @section loads

local ops = {}

local function moveslot(f, state, a, b)
	local value = state[b]
	if value ~= nil and (value.t & CARRIED) ~= 0 then
		setreg(f, a, fetch(f, b, reg.R1))
	end
	state[a] = value
end

function ops.MOVE(f, pc, ins, state)
	moveslot(f, state, ins.a, ins.b)
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
	if maps.declares(env) then
		mapnumber(f, pc, "key")
	end
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
	if container ~= nil and container.t == CTX then
		return contextget(f, pc, ins, state, key)
	end
	if container ~= nil and container.t == RECORD then
		return mapfield(f, pc, ins, state, container, key)
	end
	if container ~= nil and maps.declares(container.k) then
		mapnumber(f, pc, "key")
	end
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key, name), key)
end

function ops.SETFIELD(f, pc, ins, state)
	local container = state[ins.a]
	if container ~= nil and container.t == CTX then
		return contextset(f, pc, ins, state, tostring(constant(f, pc, ins.b)))
	end
	if container ~= nil and container.t == RECORD then
		refuse(f, pc, "a struct map value is read-only in a compiled function")
	end
	mapof(f, pc, state, ins.a)
	mapnumber(f, pc, "key")
end

-- a global is a field of the _ENV upvalue, and so is any other upvalue table's
function ops.SETTABUP(f, pc, ins, state)
	if maps.declares((upvalue(f, pc, ins.a))) then
		mapnumber(f, pc, "key")
	end
	refuse(f, pc, "a global cannot be assigned in a compiled function")
end

function ops.SETTABLE(f, pc, ins, state)
	local map = mapof(f, pc, state, ins.a)
	if not isinteger(state[ins.b]) then
		mapnumber(f, pc, "key")
	end
	mapstore(f, pc, ins, state, map, getreg(f, pc, state, ins.b, reg.R3))
end

function ops.SETI(f, pc, ins, state)
	local map = mapof(f, pc, state, ins.a)
	f.code:set(reg.R3, ins.b)
	mapstore(f, pc, ins, state, map, reg.R3)
end

function ops.GETI(f, pc, ins, state)
	local container = state[ins.b]
	if container ~= nil and maps.declares(container.k) then
		f.code:set(reg.R3, ins.c)
		return maplookup(f, ins, state, container.k, reg.R3)
	end
	local name = container ~= nil and container.name or "a table"
	resolve(f, pc, state, ins.a, lookup(f, pc, container, ins.c, name))
end

function ops.GETTABLE(f, pc, ins, state)
	local key = state[ins.c]
	local container = state[ins.b]
	if container ~= nil and maps.declares(container.k) then
		return mapread(f, pc, ins, state, container.k)
	end
	local name = container ~= nil and container.name or "a table"
	if key == nil or key.k == nil then
		refuse(f, pc, "'%s' is indexed by a value the compiler cannot resolve", name)
	end
	resolve(f, pc, state, ins.a, lookup(f, pc, container, key.k, name))
end

-- the receiver goes to A+1 and the method to A, which the call then reads back
function ops.SELF(f, pc, ins, state)
	local recv = state[ins.b]
	if recv == nil or (recv.t & PROXY) == 0 then
		refuse(f, pc, "a method call cannot be compiled")
	end
	moveslot(f, state, ins.a + 1, ins.b)
	state[ins.a] = {t = METHOD, name = tostring(constant(f, pc, ins.c)), recv = recv}
end

function ops.LEN(f, pc, ins, state)
	local value = state[ins.b]
	if value == nil or value.t ~= PACKET then
		refuse(f, pc, "'#' cannot be applied in a compiled function")
	end
	packetlen(f, ins, state)
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
	if mask == 0 or (mask & ~(BOOL | NIL | UNTESTED)) ~= 0 then
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

-- the upper bound each arm of a comparison against a constant proves, as a delta on it: what
-- bounds the length a getstring reads, where the program tested it itself
local upperbound = {LT = {[true] = -1}, LE = {[true] = 0}, GT = {[false] = 0}, GE = {[false] = -1},
	EQ = {[true] = 0}}

local function narrowed(state, i, relation, value, holds)
	local delta, a = upperbound[relation][holds], state[i]
	if delta == nil or a == nil or a.t ~= INT or (a.bound ~= nil and a.bound <= value + delta) then
		return state
	end
	local out = copy(state)
	out[i] = {t = INT, k = a.k, name = a.name, bound = value + delta}
	return out
end

-- the states the two arms of a test carry: the jump is taken where the relation holds as the
-- opcode's k says, and the other arm is where it does not
local function arms(state, i, relation, value, k)
	if type(value) ~= "number" then
		return state, state
	end
	return narrowed(state, i, relation, value, k), narrowed(state, i, relation, value, not k)
end

local function ordered(f, pc, relation, a, b)
	tested(f, pc, a, b)
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
	local taken, fallen = arms(state, ins.a, relation, b ~= nil and b.k or nil, ins.k)
	into(f, pc, state, ins.a, reg.R1)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1,
		getreg(f, pc, state, ins.b, reg.R2), taken, fallen)
end

function ops.EQ(f, pc, ins, state) return compare(f, pc, ins, state, "EQ", state[ins.b]) end
function ops.LT(f, pc, ins, state) return compare(f, pc, ins, state, "LT", state[ins.b]) end
function ops.LE(f, pc, ins, state) return compare(f, pc, ins, state, "LE", state[ins.b]) end

local function compareconst(f, pc, ins, state, relation, value)
	local a, b = state[ins.a], {t = typeof(value), k = value}
	if relation == "EQ" and b.t == NIL and a ~= nil and a.t == ANSWER then
		return testanswer(f, pc, ins, state, ins.k)
	end
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
	local taken, fallen = arms(state, ins.a, relation, value, ins.k)
	into(f, pc, state, ins.a, reg.R1)
	f.code:set(reg.R2, operand)
	return testjump(f, pc, state, relations[relation][ins.k], reg.R1, reg.R2, taken, fallen)
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
	local value = state[ins.a]
	if value ~= nil and value.t == MAYBE then
		return testlookup(f, pc, ins, state)
	end
	if value ~= nil and value.t == ANSWER then
		return testanswer(f, pc, ins, state, not ins.k)
	end
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
		moveslot(f, state, ins.a, ins.b)
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
		local value = state[i]
		if value.t == BUFFER then
			refuse(f, pc, "a string does not outlive the function that read it")
		end
		f.rettype = f.rettype | value.t
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

-- a compiled call answers with one value, so Lua fills every further result asked for with nil
local function filled(f, pc, ins, state)
	for i = ins.a + 1, ins.a + ins.c - 2 do
		resolve(f, pc, state, i, nil)
	end
end

function ops.CALL(f, pc, ins, state)
	local callee = state[ins.a]
	if ins.b == 0 or ins.c == 0 then
		refuse(f, pc, "a call with a variable number of values cannot be compiled")
	end
	if callee ~= nil and callee.t == METHOD then
		method(f, pc, ins, state, callee)
		return filled(f, pc, ins, state)
	end
	if callee ~= nil and runtimes.declares(callee.k) then
		runtimecall(f, pc, ins, state, callee)
		return filled(f, pc, ins, state)
	end
	if callee == nil or type(callee.k) ~= "function" then
		refuse(f, pc, "a call through a value the compiler cannot resolve")
	end
	if getinfo(callee.k, "S").what == "C" then
		refuse(f, pc, "'%s' is not a Lua function this program file declares", callee.name or "?")
	end
	local nargs = ins.b - 1
	if nargs > MAXARGS then
		refuse(f, pc, "a compiled function takes at most %d arguments, not %d", MAXARGS, nargs)
	end
	local params = {}
	for i = 1, nargs do
		local value = state[ins.a + i]
		local kind = value ~= nil and value.t or 0
		if kind ~= INT and kind ~= PACKET then
			refuse(f, pc, "argument #%d is a %s, and a compiled call passes numbers and packets",
				i, typename(value))
		end
		params[i] = kind
	end
	local target = emit.subprogram(f, pc, callee.k, callee.name, params)
	for i = 1, nargs do
		move(f, fetch(f, ins.a + i, reg.R0 + i), reg.R0 + i)
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
	filled(f, pc, ins, state)
end

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
	handlers[op] = ops[name]
end

local function walk(f)
	local code = insn.new()
	f.code = code
	f.labels = {}
	f.aborted = nil
	f.rettype = 0
	f.calls = {}
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
	-- below NREGS no register spills, and the words every frame reserves are its whole depth
	grow(f, 1, max((f.proto.maxstacksize - NREGS + RESERVED) * SLOT, RESERVED * SLOT))
	if f.proto.isvararg then
		refuse(f, 1, "a vararg function cannot be compiled")
	end
	f.entry = {}
	f.bounded = {}
	f.regions = {}
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
--   with <m>`, `'<name>' is called with a <type> and compiled with a <type>`, or `'<name>'
--   takes <n> arguments and is called with <m>`
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
	return frame(unit, fn, read, name, params, false)
end

---
-- Compiles one program: its function, and every function that function reaches.
-- @function luaebpf.emit.program
-- @tparam table program `{name, fn, default, drop, allowed, names, context, kfunc}`
-- @treturn table the frames, the program's own first
-- @raise `a program takes one argument, the context`, and `<file>:<line>: <reason>` for every
--   construct the subset refuses
function emit.program(program)
	local unit = {
		functions = {}, order = {}, lowering = {}, names = program.names or {},
		default = program.default, drop = program.drop, context = program.context,
		kfunc = program.kfunc, allowed = program.allowed, offers = {},
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

