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
-- naming the Lua file and line.
--
-- The compiler runs on the machine that loads what it emits, so it reads the running kernel
-- rather than being told which kernel to target.
-- @module luaebpf
-- @usage
-- local luaebpf = require("luaebpf")
--
-- local object = luaebpf.compile("filter.bpf.lua")

local programs = require("luaebpf.programs")
local proto    = require("luaebpf.proto")
local emit     = require("luaebpf.emit")
local insn     = require("luaebpf.insn")
local elf      = require("luaebpf.elf")
local btf      = require("luaebpf.btf")

local insert = table.insert
local concat = table.concat
local format = string.format
local getenv = os.getenv

local SECTION <const> = "xdp"
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
	return btf.funcinfo(at, types:func(frame.name, #frame.params, btf.linkage.GLOBAL,
		{result = types.int, param = types.long}))
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

-- what the "xdp" section holds: every program's code, and the records that name each program's
-- first instruction and the Lua line every instruction came from
local function blob(name)
	return {name = name, code = {}, funcs = {}, lines = {}, at = 0}
end

local function place(types, unit, frame, cache)
	local at = unit.at
	insert(unit.code, frame.code:pack())
	insert(unit.funcs, funcinfo(types, frame, at))
	for _, record in ipairs(lineinfo(types, frame, at, cache)) do
		insert(unit.lines, record)
	end
	unit.at = at + frame.code:len() * insn.SIZE
	return at
end

local function btfsection(object, name, data)
	object:section{name = name, type = elf.section.PROGBITS, flags = 0, data = data, align = 4}
end

local function write(declared, hook)
	local object, types, cache = elf.new(), btf.new(), {}
	local entries, names, order = blob(SECTION), {}, {}
	for _, program in ipairs(declared) do
		program.drop = hook
		program.names = names
		local frame = emit.program(program)[1]
		local at = place(types, entries, frame, cache)
		insert(order, {name = frame.name, section = SECTION, value = at,
			size = frame.code:len() * insn.SIZE, bind = elf.bind.GLOBAL})
	end

	object:section{name = entries.name, type = elf.section.PROGBITS,
		flags = elf.flags.ALLOC | elf.flags.EXEC, data = concat(entries.code), align = 8}
	for _, entry in ipairs(order) do
		object:symbol(entry)
	end

	object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC |
		elf.flags.WRITE, data = LICENSE .. "\0", align = 1}
	local ext = types:ext({{name = entries.name, funcs = entries.funcs,
		lines = hook ~= "lineinfo" and entries.lines or {}}})
	btfsection(object, ".BTF", types:pack())
	btfsection(object, ".BTF.ext", ext)
	return object:pack()
end

local function name(program, chunk)
	return program.name or (chunk:match("([^/]+)$"):gsub("%.bpf%.lua$", ""):gsub("%.lua$", ""))
end

---
-- Compiles the program file at `path`.
-- @function luaebpf.compile
-- @tparam string path the program file, usually named `<something>.bpf.lua`
-- @treturn string the BPF ELF object
-- @raise `<file>:<line>: <reason>` for every construct the subset refuses, and
--   `<path>: no program declared` when the body hands nothing to a constructor
function luaebpf.compile(path)
	local chunk = proto.load(path)
	programs.reset()
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
	return write(declared, getenv(DROP))
end

return luaebpf

