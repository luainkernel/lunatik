--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The programs a case's program file declares to keep what they compute (see common.sh): each
-- hands its value to a function that stores it in the map `results`, under a key of its own, and
-- returns its default verdict, the map holding the 64 bits of a value where a verdict is an action.
-- A corpus row is handed to the constructor its context's program type takes, xdp.program where
-- it names no context, and what its program keeps when the CLI's Lua runs it on the twin of that
-- context is written beside the object, which the case compares against what the compiled program
-- kept. A program file's body requires it, so it installs with the kernel scripts and loads through
-- lunatic, which makes that answer the one the kernel computes; nothing runs it in the kernel.

local class   = require("class")
local vmlinux = require("luaebpf.vmlinux")
local packets = require("tests.luaebpf.packets")
local map     = require("bpf.map")
local xdp     = require("bpf.xdp")
local tc      = require("bpf.tc")

local pack, unpack     = string.pack, string.unpack
local tabunpack, insert = table.unpack, table.insert
local concat            = table.concat

local U32MAX   <const> = 0xffffffff -- the largest value luaskb_integer stores
local ORACLE   <const> = "oracle.txt"
local KEYS     <const> = "keys.txt"
local RESULTS  <const> = "results"
local KEY      <const> = "I4"
local VALUE    <const> = "i8" -- a Lua integer, whole
local LOOPBACK <const> = 1
local QUEUE    <const> = 0
local FRAME    <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local corpus = {}

local rows = class{}

-- the packet as the kernel's data object reads it: string.unpack with a native-order format of
-- the exact width, which is the load the emitter lowers each accessor to, rather than a second
-- implementation of its shifts
local packet = class{}

-- what a twin is called and what it carries, kept outside it so that a kernel context struct may
-- have a member of any name
local states = setmetatable({}, {__mode = "k"})

-- the program type whose context each struct is
local constructors = {xdp_md = xdp.program, __sk_buff = tc.program}

local function read(self, format, at)
	if at < 0 then
		error("offset out of bounds", 0)
	end
	return (unpack(format, self.bytes, at + 1))
end

function packet:getbyte(at) return read(self, "=I1", at) end
function packet:getuint8(at) return read(self, "=I1", at) end
function packet:getint8(at) return read(self, "=i1", at) end
function packet:getuint16(at) return read(self, "=I2", at) end
function packet:getint16(at) return read(self, "=i2", at) end
function packet:getuint32(at) return read(self, "=I4", at) end
function packet:getint32(at) return read(self, "=i4", at) end
function packet:getint64(at) return read(self, "=i8", at) end

function packet.__len(self)
	return #self.bytes
end

-- the XDP context the interpreted side is handed, spelled as the kernel's XDP ctx object
-- (lib/luaxdp.c), over the fields prog run was given, and the packet behind :packet()
local context = class{}

function context:ingress()
	return states[self].fields.ingress_ifindex
end

function context:queue()
	return states[self].fields.rx_queue_index
end

function context:packet()
	return states[self].packet
end

-- the skb the interpreted side is handed, spelled as the kernel's skb object (lib/luaskb.c), over
-- the fields prog run was given, and the packet behind :data()
local skb = class{}

function skb.__len(self)
	return states[self].fields.len
end

function skb:ifindex()
	return states[self].fields.ifindex
end

-- convert___skb_to_skb refuses a ctx_in that sets the hash, and the skb prog run builds has none
function skb:hash()
	return 0
end

-- luaskb_integer: a value is stored, within the 32 bits the field has, and the field is returned
function skb:priority(value)
	local fields = states[self].fields
	if value ~= nil then
		if value < 0 or value > U32MAX then
			error("out of bounds", 0)
		end
		fields.priority = value
	end
	return fields.priority
end

function skb:data()
	return states[self].packet
end

local function write(path, bytes)
	local file = assert(io.open(path, "wb"))
	file:write(bytes)
	file:close()
end

-- the context struct bpftool builds its own from: zero everywhere but the fields named here,
-- each at the offset the kernel's own BTF reports, so a wrong offset makes prog run fill a
-- different field than the program reads
local function contextbytes(what, fields)
	local layout = vmlinux.layout(what)
	local bytes = ("\0"):rep(layout.size)
	for _, field in ipairs(layout.fields) do
		local value = fields[field.name]
		if value ~= nil then
			bytes = bytes:sub(1, field.offset) .. pack("=I" .. field.size, value)
				.. bytes:sub(field.offset + field.size + 1)
		end
	end
	return bytes
end

-- the stimulus both sides are handed: the bytes bpftool prog run builds its context from and the
-- packet, written beside the object as <name>.ctx and <name>.bin, and the twin the body runs the
-- interpreted function against
function corpus.context(name, what, fields, bytes)
	if what == "xdp_md" then
		-- bpf_prog_test_run_xdp sizes the packet from ctx_in.data_end, empty when it is zero (test_run.c)
		fields.data_end = #bytes
	end
	write(name .. ".ctx", contextbytes(what, fields))
	write(name .. ".bin", bytes)
	local twin
	if what == "__sk_buff" then
		-- convert___skb_to_skb refuses a non-zero __sk_buff.len and sizes skb->len from the packet
		fields.len = #bytes
		twin = skb:new()
	else
		twin = context:new()
	end
	states[twin] = {name = name, packet = packet:new{bytes = bytes}, program = constructors[what],
		fields = fields}
	return twin
end

-- an XDP context on loopback, whose generic rx queue 0 has its xdp_rxq registered on every
-- device, which is what xdp_convert_md_to_buff requires of a non-zero ingress_ifindex
-- (net/bpf/test_run.c)
local function loopback(name, bytes)
	return corpus.context(name, "xdp_md", {ingress_ifindex = LOOPBACK, rx_queue_index = QUEUE}, bytes)
end

-- a TC context over a packet, which prog run builds on loopback when ctx_in names no device
local function sched(name, bytes)
	return corpus.context("skb" .. name, "__sk_buff", {}, bytes)
end

-- every packet of packets.lua behind a context of its own, by the packet's name
local function bypacket(build)
	local contexts = {}
	for _, name in ipairs(packets.order) do
		contexts[name] = build(name, packets[name])
	end
	return contexts
end

-- the corpus behind XDP contexts
function corpus.packets()
	return bypacket(loopback)
end

-- the corpus behind TC contexts
function corpus.skbpackets()
	return bypacket(sched)
end

-- the fourteen bytes BPF_PROG_TEST_RUN demands of an XDP program, behind a context named "frame",
-- for a case whose programs read a map rather than the packet
function corpus.frame()
	return loopback("frame", FRAME)
end

-- a packed value's bytes as bpftool takes and prints them, each formatted with how, "%d" when nil
function corpus.bytes(packed, how)
	local out = {}
	for i = 1, #packed do
		insert(out, (how or "%d"):format(packed:byte(i)))
	end
	return concat(out, " ")
end

-- what the programs keep, by key: a table while the body runs them on the host, which the oracle
-- reads, and from corpus.close the map a compiled program's keep writes
local kept = {}
local names = {}

local function keeper(key)
	return function(v)
		kept[key] = v
	end
end

-- declares the program build(keep, ...) makes, whose keep stores what the program hands it under
-- a key of the program's own; answers the declared program and that key
function corpus.program(constructor, opts, build, ...)
	insert(names, opts.name)
	local key = #names
	return constructor(build(keeper(key), ...), opts), key
end

-- the program of a function of no context, which keeps what the function returns: the function is
-- handed a 0 for the argument it ignores, since a compiled call passes every one the callee declares
function corpus.returning(keep, fn)
	return function(_)
		local v = fn(0)
		keep(v)
	end
end

-- declares the map the programs keep their values in, once every one of them is declared, and
-- writes the key each keeps under beside the object, where luaebpf_kept reads it
function corpus.close()
	kept = map.hash(RESULTS, {key = KEY, value = VALUE, entries = #names})
	local out = assert(io.open(KEYS, "w"))
	for key, name in ipairs(names) do
		out:write(name, "\t", corpus.bytes(pack(KEY, key)), "\n")
	end
	out:close()
end

function corpus.new()
	return rows:new{out = assert(io.open(ORACLE, "w"))}
end

-- the oracle's line for a row: what its program kept when the body ran it, "absent" where it raised
-- before keeping anything
local function answer(self, program, key, ctx)
	pcall(program.fn, ctx)
	local value = kept[key]
	self.out:write(program.name, "\t", value ~= nil and tostring(value) or "absent", "\t", program.default, "\t",
		ctx ~= nil and states[ctx].name or "", "\n")
end

-- a row over a function of no context, whose program keeps what it returns
function rows:declare(name, fn, default)
	answer(self, corpus.program(xdp.program, {name = name, default = default}, corpus.returning, fn))
end

-- a row over the program build(keep) makes, of the type whose context ctx is the twin of
function rows:stores(name, build, default, ctx)
	local program, key = corpus.program(states[ctx].program, {name = name, default = default}, build)
	answer(self, program, key, ctx)
end

function rows:close()
	self.out:close()
	corpus.close()
end

-- a row per maker in order and argument list in operands, named after the maker and the list's place
function corpus.declare(makers, order, operands, default)
	local declared = corpus.new()
	for _, op in ipairs(order) do
		for i, args in ipairs(operands) do
			declared:declare(op .. i, makers[op](tabunpack(args)), default)
		end
	end
	declared:close()
end

return corpus

