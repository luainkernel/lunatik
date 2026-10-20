--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The rows a corpus case's program file declares (see common.sh): each is handed to
-- xdp.program, and what the CLI's Lua answers for it is written beside the object, which the
-- case compares against what the compiled program returns. A program file's body requires it,
-- so it installs with the kernel scripts and loads through lunatic, which makes that answer the
-- one the kernel computes; nothing runs it in the kernel.

local class   = require("class")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local pack   = string.pack
local unpack = table.unpack

local VERDICT <const> = 0xffffffff -- the 32 bits bpf_prog_run returns
local ORACLE  <const> = "oracle.txt"

local corpus = {}

local rows = class{}

-- what a twin is called and what it carries, kept outside it so that a kernel context struct may
-- have a member of any name
local states = setmetatable({}, {__mode = "k"})

-- the XDP context the interpreted side is handed, spelled as the kernel's XDP ctx object
-- (lib/luaxdp.c), over the fields prog run was given
local context = class{}

function context:ingress()
	return states[self].fields.ingress_ifindex
end

function context:queue()
	return states[self].fields.rx_queue_index
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
	write(name .. ".ctx", contextbytes(what, fields))
	write(name .. ".bin", bytes)
	local twin = context:new()
	states[twin] = {name = name, fields = fields}
	return twin
end

local function answer(ok, value)
	if not ok then
		return "raises"
	end
	if type(value) == "boolean" then
		return value and "1" or "0"
	end
	return tostring(value & VERDICT)
end

function corpus.new()
	return rows:new{out = assert(io.open(ORACLE, "w"))}
end

function rows:declare(name, fn, default, ctx)
	local program = xdp.program(fn, {name = name, default = default})
	self.out:write(name, "\t", answer(pcall(fn, ctx or 0)), "\t", program.default, "\t",
		ctx ~= nil and states[ctx].name or "", "\n")
end

function rows:close()
	self.out:close()
end

-- a row per maker in order and argument list in operands, named after the maker and the list's place
function corpus.declare(makers, order, operands, default)
	local declared = corpus.new()
	for _, op in ipairs(order) do
		for i, args in ipairs(operands) do
			declared:declare(op .. i, makers[op](unpack(args)), default)
		end
	end
	declared:close()
end

return corpus

