--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Compiles a Lua program file into a BPF ELF object.
--
-- A program file's body is compile-time Lua: it runs once, on the host, under the kernel's own
-- Lua build, and hands the functions it declares to a program constructor. Those functions are
-- the program: `compile` reads their bytecode, lowers it, and writes an object `bpftool prog
-- load` accepts. Anything the subset refuses is an error naming the Lua file and line.
--
-- The compiler runs on the machine that loads what it emits, so it reads the running kernel
-- rather than being told which kernel to target.
-- @module luaebpf
-- @usage
-- local luaebpf = require("luaebpf")
--
-- local object = luaebpf.compile("filter.bpf.lua")

local programs = require("luaebpf.programs")

local insert = table.insert
local concat = table.concat
local format = string.format

local PROTO   <const> = "luaebpf.proto"
local SECTION <const> = "xdp"
local TEXT    <const> = ".text"
local LICENSE <const> = "Dual MIT/GPL"
local HOSTED  <const> = "luaebpf.proto is missing; a program file compiles under 'lunatikc bpf'"
local DROP    <const> = "LUAEBPF_DROP"

local emit, insn, elf, btf
if package.loaded[PROTO] ~= nil then
	emit = require("luaebpf.emit")
	insn = require("luaebpf.insn")
	elf  = require("luaebpf.elf")
	btf  = require("luaebpf.btf")
end

local luaebpf = {}

local function readlines(path)
	local file = io.open(path, "r")
	if file == nil then
		return {}
	end
	local lines = {}
	for line in file:lines("l") do
		insert(lines, line)
	end
	file:close()
	return lines
end

-- the host Lua has no 'os', and the emitter's test hook is named by the environment
local function drop()
	local file = io.open("/proc/self/environ", "rb")
	if file == nil then
		return nil
	end
	local environ = file:read("a")
	file:close()
	return environ:match("%f[^%z]" .. DROP .. "=([^%z]*)")
end

local function sources(chunk, cache)
	local lines = cache[chunk]
	if lines == nil then
		lines = readlines(chunk)
		cache[chunk] = lines
	end
	return lines
end

local function funcinfo(types, frame, at)
	local signature = frame.isprogram and {result = types.int, param = types.long}
		or {result = types.long, param = types.long}
	local linkage = frame.isprogram and btf.linkage.GLOBAL or btf.linkage.STATIC
	return btf.funcinfo(at, types:func(frame.name, #frame.params, linkage, signature))
end

local function lineinfo(types, frame, at, cache)
	local records, lines, previous = {}, frame.code:sourcelines(), nil
	local file = types:string(frame.chunk)
	local text = sources(frame.chunk, cache)
	for i = 1, #lines do
		if lines[i] ~= previous then
			insert(records, btf.lineinfo(at + (i - 1) * insn.SIZE, file,
				types:string(text[lines[i]] or ""), lines[i], 1))
			previous = lines[i]
		end
	end
	return records
end

-- one blob per ELF section: the program entries in "xdp", every subprogram in ".text", which
-- is where libbpf resolves a call relocation
local function blob(name)
	return {name = name, code = {}, funcs = {}, lines = {}, relocations = {}, at = 0}
end

local function place(types, unit, frame, cache, subprograms)
	local at = unit.at
	insert(unit.code, frame.code:pack())
	insert(unit.funcs, funcinfo(types, frame, at))
	for _, record in ipairs(lineinfo(types, frame, at, cache)) do
		insert(unit.lines, record)
	end
	for _, call in ipairs(frame.code:relocations()) do
		insert(unit.relocations, {at = at + (call.at - 1) * insn.SIZE, name = call.name})
	end
	unit.at = at + frame.code:len() * insn.SIZE
	if not frame.isprogram then
		insert(subprograms, {name = frame.name, section = TEXT, value = at,
			size = frame.code:len() * insn.SIZE, bind = elf.bind.LOCAL})
	end
	return at
end

local function write(declared, hook)
	local object, types, cache = elf.new(), btf.new(), {}
	local entries, text = blob(SECTION), blob(TEXT)
	local names, subprograms, order = {}, {}, {}
	for _, program in ipairs(declared) do
		program.drop = hook
		program.names = names
		for i, frame in ipairs(emit.program(program)) do
			local unit = i == 1 and entries or text
			local at = place(types, unit, frame, cache, subprograms)
			if i == 1 then
				insert(order, {name = frame.name, section = SECTION, value = at,
					size = frame.code:len() * insn.SIZE, bind = elf.bind.GLOBAL})
			end
		end
	end

	local indexes = {}
	for _, unit in ipairs({text, entries}) do
		if unit.at > 0 then
			object:section{name = unit.name, type = elf.section.PROGBITS,
				flags = elf.flags.ALLOC | elf.flags.EXEC, data = concat(unit.code), align = 8}
		end
	end
	for _, subprogram in ipairs(subprograms) do
		indexes[subprogram.name] = object:symbol(subprogram)
	end
	for _, entry in ipairs(order) do
		object:symbol(entry)
	end
	for _, unit in ipairs({text, entries}) do
		local records = {}
		for _, call in ipairs(unit.relocations) do
			insert(records, {at = call.at, symbol = indexes[call.name]})
		end
		if #records > 0 then
			object:relocations(unit.name, records)
		end
	end

	object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC |
		elf.flags.WRITE, data = LICENSE .. "\0", align = 1}
	local sections = {}
	for _, unit in ipairs({entries, text}) do
		if unit.at > 0 then
			insert(sections, {name = unit.name, funcs = unit.funcs,
				lines = hook ~= "lineinfo" and unit.lines or {}})
		end
	end
	local ext = types:ext(sections)
	object:section{name = ".BTF", type = elf.section.PROGBITS, flags = 0, data = types:pack(), align = 4}
	object:section{name = ".BTF.ext", type = elf.section.PROGBITS, flags = 0, data = ext, align = 4}
	return object:pack()
end

local function name(program, chunk, taken)
	if program.name ~= nil then
		taken[program.name] = true
		return program.name
	end
	local base = chunk:match("([^/]+)$"):gsub("%.bpf%.lua$", ""):gsub("%.lua$", "")
	local candidate, n = base, 1
	while taken[candidate] do
		n = n + 1
		candidate = base .. n
	end
	taken[candidate] = true
	return candidate
end

---
-- Compiles the program file at `path`.
-- @function luaebpf.compile
-- @tparam string path the program file, usually named `<something>.bpf.lua`
-- @treturn string the BPF ELF object
-- @raise `luaebpf.proto is missing` when the host provides no prototype accessor,
--   `<file>:<line>: <reason>` for every construct the subset refuses, and
--   `<path>: no program declared` when the body hands nothing to a constructor
function luaebpf.compile(path)
	if emit == nil then
		error(HOSTED, 0)
	end
	local chunk, err = loadfile(path)
	if chunk == nil then
		error(err, 0)
	end
	programs.reset()
	local ok, message = pcall(chunk)
	if not ok then
		error(message, 0)
	end
	local declared, taken = programs.declared(), {}
	if #declared == 0 then
		error(format("%s: no program declared", path), 0)
	end
	for _, program in ipairs(declared) do
		program.name = name(program, path, taken)
	end
	return write(declared, drop())
end

return luaebpf

