--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Compiles a Lua program file into a BPF ELF object.
--
-- A program file's body is compile-time Lua: `lunatic` compiles the file, and the body runs once,
-- on the host, from that bytecode in the CLI's Lua, and hands the functions it declares to a
-- program constructor. Those functions are the program: `compile` reads their bytecode, lowers it,
-- and returns an object `bpftool prog load` accepts. Anything the subset refuses is an error
-- naming the Lua file and line. `lunatik bpf` calls `compile` and writes the object, which
-- `lunatik run --dev` loads and attaches; the guide page *Compiling Lua to eBPF* says what a
-- program file may hold, what a program returns and when it stops.
--
-- The compiler compiles for the kernel `lunatik.config` describes, which `make` writes from the
-- tree Lunatik is built against: that kernel's version and byte order. It reads that kernel's types
-- from the BTF file it is handed, or from `/sys/kernel/btf/vmlinux`, the running kernel's, so a
-- build host compiles for the kernel an image ships when `make` was handed that kernel's tree and
-- the compiler its BTF.
--
-- Experimental: the compiler, `lunatik bpf`, `lunatik run --dev` and the modules a program file's
-- body requires may change in a minor release.
-- @module luaebpf
-- @usage
-- local luaebpf = require("luaebpf")
--
-- local object = luaebpf.compile("filter.bpf.lua")
-- local image = luaebpf.compile("filter.bpf.lua", "build/vmlinux.btf")

local maps     = require("luaebpf.maps")
local programs = require("luaebpf.programs")
local proto    = require("luaebpf.proto")
local emit     = require("luaebpf.emit")
local insn     = require("luaebpf.insn")
local elf      = require("luaebpf.elf")
local btf      = require("luaebpf.btf")
local vmlinux  = require("luaebpf.vmlinux")

local insert = table.insert
local concat = table.concat
local format = string.format
local getenv = os.getenv

local TEXT    <const> = ".text"
local MAPS    <const> = ".maps"
local KSYMS   <const> = ".ksyms"
local LICENSE <const> = "Dual MIT/GPL"
local DROP    <const> = "LUAEBPF_DROP"

local LIBPATH <const> = select(2, ...):match("^(.*/)") .. "lib/?.lua"

-- the host's path, through which a body still reaches the compiler's own modules
local HOSTPATH <const> = package.path

local function own(name)
	if name:find("^luaebpf%.") then
		local path, err = package.searchpath(name, HOSTPATH)
		if path == nil then
			return err
		end
		return assert(loadfile(path)), path
	end
end
insert(package.searchers, #package.searchers, own) -- the compiler's luaebpf.*, ahead of the kernel scripts' searcher

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
	return types:funcinfo(at, types:func(frame.name, linkage, signature))
end

local function lineinfo(types, frame, at, cache)
	local records, lines, previous = {}, frame.code:sourcelines(), nil
	local file = types:string(frame.chunk)
	local text = sources(frame.chunk, cache)
	for i = 1, #lines do
		if lines[i] ~= previous then
			insert(records, types:lineinfo(at + (i - 1) * insn.SIZE, file,
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

local function place(types, unit, frame, cache, subprograms)
	local at = unit.at
	insert(unit.code, frame.code:pack(emit.bigendian))
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
	for _, call in ipairs(frame.code:relocations("kfunc")) do
		insert(unit.relocations, {at = at + (call.at - 1) * insn.SIZE, name = call.name,
			type = elf.relocation.IMM32})
	end
	unit.at = at + frame.code:len() * insn.SIZE
	if not frame.isprogram then
		insert(subprograms, {name = frame.name, section = TEXT, value = at,
			size = frame.code:len() * insn.SIZE, bind = elf.bind.LOCAL, type = elf.type.FUNC})
	end
	return at
end

local function btfsection(object, name, data)
	object:section{name = name, type = elf.section.PROGBITS, flags = 0, data = data, align = 4}
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

-- The prototype libbpf compares with the kernel's kind by kind, names and integer widths aside
-- (tools/lib/bpf/relo_core.c): a pointer to an empty struct of the context's name stands for the
-- context, and a pointer to type 0 for the void the argument goes as.
local function prototype(types, context)
	return {result = types.int, params = {types:pointer(types.int), types.long,
		types:pointer((types:struct(context, {}))), types:pointer(0), types.long}}
end

-- each kfunc a call names: a FUNC of extern linkage listed in a DATASEC named ".ksyms", whose bytes
-- libbpf never looks for in the ELF, and the undefined symbol the call's relocation names
local function ksyms(types, externs, hook)
	local entries, symbols = {}, {}
	for _, extern in ipairs(externs) do
		insert(entries, {type = types:func(extern.name, btf.linkage.EXTERN, prototype(types, extern.context)),
			offset = 0, size = 0})
		insert(symbols, {name = extern.name, value = 0, size = 0, bind = elf.bind.GLOBAL,
			type = elf.type.NOTYPE})
	end
	if #entries > 0 and hook ~= "ksyms" then
		types:datasec(KSYMS, entries)
	end
	return symbols
end

local function write(declared, hook)
	local object, types, cache = elf.new(emit.bigendian), btf.new(emit.bigendian), {}
	local text = blob(TEXT)
	local units, sections = {text}, {}
	local names, subprograms, order, externs, called, calls = {}, {}, {}, {}, {}, {}
	-- maps and kfuncs take their names before any function does, so a relocation names one symbol
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
			local at = place(types, unit, frame, cache, subprograms)
			for _, call in ipairs(frame.calls) do
				insert(calls, format("%s:%d: calls the runtime '%s'", frame.chunk, call.line, call.key))
			end
			if not called[program.kfunc] and #frame.code:relocations("kfunc") > 0 then
				called[program.kfunc] = true
				insert(externs, {name = program.kfunc, context = program.context.struct})
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
	local kfuncs = ksyms(types, externs, hook)
	for _, subprogram in ipairs(subprograms) do
		indexes[subprogram.name] = object:symbol(subprogram)
	end
	for _, entry in ipairs(order) do
		object:symbol(entry)
	end
	for _, symbol in ipairs(mapsymbols) do
		indexes[symbol.name] = object:symbol(symbol)
	end
	for _, symbol in ipairs(kfuncs) do
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
	local ext = types:ext(described) -- it interns the section names in .BTF's strings, so before pack
	btfsection(object, ".BTF", types:pack())
	btfsection(object, ".BTF.ext", ext)
	return object:pack(), calls
end

local function name(program, chunk)
	return program.name or (chunk:match("([^/]+)$"):gsub("%.bpf%.lua$", ""):gsub("%.lua$", ""))
end

---
-- Compiles the program file at `path`.
-- @function luaebpf.compile
-- @tparam string path the program file, usually named `<something>.bpf.lua`
-- @tparam[opt] string btffile the kernel's BTF as a raw BTF file, the bytes
--   `/sys/kernel/btf/vmlinux` serves, read once a layout is asked for; that file when absent
-- @treturn string the BPF ELF object
-- @treturn table a line per call into the kernel Lua runtime the compiler met, in that order,
--   `<file>:<line>: calls the runtime '<name>'`
-- @raise `<file>:<line>: <reason>` for every construct the subset refuses,
--   `<path>: no program declared` when the body hands nothing to a constructor,
--   `<btffile>: <reason>`, `<btffile> carries no BTF header` and `<btffile> is shorter than its
--   BTF header says` when a layout is asked of a file that cannot be read, holds no BTF or is cut
--   short, and `<btffile> is a <order>-endian BTF, for a <order>-endian object` when the BTF a
--   layout was read from is not in the object's byte order
function luaebpf.compile(path, btffile)
	local chunk = proto.load(path)
	programs.reset()
	maps.reset()
	vmlinux.open(btffile)
	local host, cpath = package.path, package.cpath
	package.path, package.cpath = LIBPATH, "" -- no host module, Lua or C, stands in for a kernel script
	local ok, message = pcall(chunk)
	package.path, package.cpath = host, cpath
	if not ok then
		error(message, 0)
	end
	local declared = programs.declared()
	if #declared == 0 then
		error(format("%s: no program declared", path), 0)
	end
	for _, program in ipairs(declared) do
		program.name = name(program, path)
	end
	local object, calls = write(declared, getenv(DROP))
	vmlinux.check(emit.bigendian)
	return object, calls
end

return luaebpf

