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

local maps     = require("luaebpf.maps")
local programs = require("luaebpf.programs")
local runtimes = require("luaebpf.runtimes")

local insert = table.insert
local concat = table.concat
local format = string.format

local PROTO   <const> = "luaebpf.proto"
local TEXT    <const> = ".text"
local MAPS    <const> = ".maps"
local KSYMS   <const> = ".ksyms"
local LICENSE <const> = "Dual MIT/GPL"
local HOSTED  <const> = "luaebpf.proto is missing; a program file compiles under 'lunatikc bpf'"
local DROP    <const> = "LUAEBPF_DROP"
local ROOT    <const> = "^/lib/modules/lua/"

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
	local params = {}
	for _ = 1, #frame.params do
		insert(params, types.long)
	end
	local signature = {result = frame.isprogram and types.int or types.long, params = params}
	local linkage = frame.isprogram and btf.linkage.GLOBAL or btf.linkage.STATIC
	return btf.funcinfo(at, types:func(frame.name, linkage, signature))
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

-- one blob per ELF section: a program's entry in the section its kind names, which is how
-- libbpf reads the program type back, and every subprogram in ".text", where libbpf resolves a
-- call relocation
local function blob(name)
	return {name = name, code = {}, funcs = {}, lines = {}, relocations = {}, at = 0}
end

local function section(units, sections, name)
	local unit = sections[name]
	if unit == nil then
		unit = blob(name)
		sections[name] = unit
		insert(units, unit)
	end
	return unit
end

local function place(types, unit, frame, cache, subprograms, called)
	local at = unit.at
	insert(unit.code, frame.code:pack())
	insert(unit.funcs, funcinfo(types, frame, at))
	for _, record in ipairs(lineinfo(types, frame, at, cache)) do
		insert(unit.lines, record)
	end
	for _, call in ipairs(frame.code:relocations("call")) do
		insert(unit.relocations, {at = at + (call.at - 1) * insn.SIZE, name = call.name,
			type = elf.relocation.IMM32})
	end
	for _, use in ipairs(frame.code:relocations("map")) do
		insert(unit.relocations, {at = at + (use.at - 1) * insn.SIZE, name = use.name,
			type = elf.relocation.IMM64})
	end
	for _, use in ipairs(frame.code:relocations("kfunc")) do
		insert(unit.relocations, {at = at + (use.at - 1) * insn.SIZE, name = use.name,
			type = elf.relocation.IMM32})
		called[use.name] = true
	end
	unit.at = at + frame.code:len() * insn.SIZE
	if not frame.isprogram then
		insert(subprograms, {name = frame.name, section = TEXT, value = at,
			size = frame.code:len() * insn.SIZE, bind = elf.bind.LOCAL, type = elf.type.FUNC})
	end
	return at
end

-- A BTF-defined map is a struct of pointer-to-array members whose element counts libbpf reads
-- as the map's attributes, a VAR of that struct allocated in ".maps", and one var_secinfo per
-- map in a DATASEC of that name (tools/lib/bpf/libbpf.c). The section's bytes are read only for
-- their length, so zeros of the right size are enough.
local function attributes(map)
	return {{name = "type", value = map.type}, {name = "max_entries", value = map.entries},
		{name = "key_size", value = map.key.size}, {name = "value_size", value = map.value.size}}
end

local function maplayout(object, types, declared)
	if #declared == 0 then
		return {}
	end
	local entries, symbols, at = {}, {}, 0
	for _, map in ipairs(declared) do
		local members = {}
		for _, attribute in ipairs(attributes(map)) do
			insert(members, {name = attribute.name,
				type = types:pointer(types:array(types.int, attribute.value))})
		end
		local id, size = types:struct(map.name, members)
		insert(entries, {type = types:var(map.name, id), offset = at, size = size})
		insert(symbols, {name = map.name, section = MAPS, value = at, size = size,
			bind = elf.bind.GLOBAL, type = elf.type.OBJECT})
		at = at + size
	end
	object:section{name = MAPS, type = elf.section.PROGBITS, flags = elf.flags.ALLOC |
		elf.flags.WRITE, data = ("\0"):rep(at), align = 8}
	types:datasec(MAPS, entries)
	return symbols
end

-- The prototype libbpf resolves a kfunc call against, which it compares with the kernel's own
-- kind by kind: names, integer widths and a struct's members are all ignored, so a PTR to an
-- empty STRUCT stands for the context and a PTR to type 0 for the void the argument goes as
-- (tools/lib/bpf/relo_core.c).
local function prototype(types, context)
	return {result = types.int, params = {types:pointer(types.int), types.long,
		types:pointer((types:struct(context, {}))), types:pointer(0), types.long}}
end

-- Every kfunc a call named: a FUNC of extern linkage listed in a DATASEC named ".ksyms", whose
-- bytes libbpf never looks for in the ELF, and an undefined symbol for the relocation to name.
-- The kfunc is the program type's, so the context its prototype takes is the program's own.
local function ksyms(types, declared, called, hook)
	local entries, symbols, seen = {}, {}, {}
	for _, program in ipairs(declared) do
		local kfunc = program.kfunc
		if called[kfunc] and not seen[kfunc] then
			seen[kfunc] = true
			insert(entries, {type = types:func(kfunc, btf.linkage.EXTERN,
				prototype(types, program.context.struct)), offset = 0, size = 0})
			insert(symbols, {name = kfunc, section = elf.UNDEF, value = 0, size = 0,
				bind = elf.bind.GLOBAL, type = elf.type.NOTYPE})
		end
	end
	if #entries > 0 and hook ~= "ksyms" then
		types:datasec(KSYMS, entries)
	end
	return symbols
end

local function write(declared, hook)
	local object, types, cache = elf.new(), btf.new(), {}
	local text = blob(TEXT)
	local units, sections = {text}, {}
	local names, subprograms, order, called, summary = {}, {}, {}, {}, {}
	-- a map's and a kfunc's name are taken first, so a relocation names exactly one symbol
	for _, map in ipairs(maps.declared()) do
		names[map.name] = true
	end
	for _, program in ipairs(declared) do
		names[program.kfunc] = true
	end
	for _, program in ipairs(declared) do
		program.drop = hook
		program.names = names
		local entries = section(units, sections, program.section)
		for i, frame in ipairs(emit.program(program)) do
			local unit = i == 1 and entries or text
			local at = place(types, unit, frame, cache, subprograms, called)
			for _, call in ipairs(frame.calls) do
				insert(summary, format("%s:%d: calls the runtime '%s'", call.chunk, call.line, call.key))
			end
			if i == 1 then
				insert(order, {name = frame.name, section = program.section, value = at,
					size = frame.code:len() * insn.SIZE, bind = elf.bind.GLOBAL,
					type = elf.type.FUNC})
			end
		end
	end

	local indexes = {}
	for _, unit in ipairs(units) do
		if unit.at > 0 then
			object:section{name = unit.name, type = elf.section.PROGBITS,
				flags = elf.flags.ALLOC | elf.flags.EXEC, data = concat(unit.code), align = 8}
		end
	end
	local mapsymbols = maplayout(object, types, maps.declared())
	local externs = ksyms(types, declared, called, hook)
	for _, subprogram in ipairs(subprograms) do
		indexes[subprogram.name] = object:symbol(subprogram)
	end
	for _, entry in ipairs(order) do
		object:symbol(entry)
	end
	for _, symbol in ipairs(mapsymbols) do
		indexes[symbol.name] = object:symbol(symbol)
	end
	for _, symbol in ipairs(externs) do
		indexes[symbol.name] = object:symbol(symbol)
	end
	for _, unit in ipairs(units) do
		local records = {}
		for _, call in ipairs(unit.relocations) do
			insert(records, {at = call.at, symbol = indexes[call.name], type = call.type})
		end
		if #records > 0 then
			object:relocations(unit.name, records)
		end
	end

	object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC |
		elf.flags.WRITE, data = LICENSE .. "\0", align = 1}
	local described = {}
	for _, unit in ipairs(units) do
		if unit.at > 0 then
			insert(described, {name = unit.name, funcs = unit.funcs,
				lines = hook ~= "lineinfo" and unit.lines or {}})
		end
	end
	local ext = types:ext(described)
	object:section{name = ".BTF", type = elf.section.PROGBITS, flags = 0, data = types:pack(), align = 4}
	object:section{name = ".BTF.ext", type = elf.section.PROGBITS, flags = 0, data = ext, align = 4}
	return object:pack(), summary
end

-- the key 'lunatik run' registers a script under: its path below the scripts root, without the
-- suffix a program file carries (bin/lunatik)
local function runtimekey(path)
	return (path:gsub(ROOT, ""):gsub("%.bpf%.lua$", ""):gsub("%.lua$", ""))
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
-- @treturn table one line per call into the kernel Lua runtime, naming the file, the line and the
--   runtime key, so a program that calls Lua on every packet is visible for what it is
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
	maps.reset()
	runtimes.reset()
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
	for _, runtime in ipairs(runtimes.declared()) do
		runtime.key = runtime.key or runtimekey(path)
	end
	return write(declared, drop())
end

return luaebpf

