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
-- from the BTF file it is handed, or from `/sys/kernel/btf/vmlinux`, the running kernel's, and the
-- kernel scripts the body requires from the directory it is handed, or from `/lib/modules/lua`, so
-- a build host compiles for the kernel an image ships when `make` was handed that kernel's tree and
-- the compiler its BTF and the image's kernel scripts.
--
-- Experimental: the compiler, `lunatik bpf`, `lunatik run --dev` and the modules a program file's
-- body requires may change in a minor release.
-- @module luaebpf
-- @usage
-- local luaebpf = require("luaebpf")
--
-- local object = luaebpf.compile("filter.bpf.lua")
-- local image = luaebpf.compile("filter.bpf.lua", "build/vmlinux.btf", "staging/lib/modules/lua")

local maps     = require("luaebpf.maps")
local programs = require("luaebpf.programs")
local proto    = require("luaebpf.proto")
local vmlinux  = require("luaebpf.vmlinux")

local insert = table.insert
local format = string.format
local getenv = os.getenv

local DROP    <const> = "LUAEBPF_DROP"

local LIBPATH <const> = select(2, ...):match("^(.*/)") .. "lib/?.lua"

-- the host's path, through which a body still reaches the compiler's own modules
local HOSTPATH <const> = package.path

-- lib/, through which the compiler reaches the bpf.runtime a call's lowering reads, one copy for it and the body
local paths = {luaebpf = HOSTPATH, bpf = LIBPATH}

local function own(name)
	local where = paths[name:match("^(%a+)%.")]
	if where ~= nil then
		local path, err = package.searchpath(name, where)
		if path == nil then
			return err
		end
		return assert(loadfile(path)), path
	end
end
insert(package.searchers, #package.searchers, own) -- ahead of the kernel scripts' searcher

local emit   = require("luaebpf.emit") -- after own: a call's lowering requires bpf.runtime
local writer = require("luaebpf.writer")

local luaebpf = {}

local function modnames()
	local names = {}
	for modname in pairs(package.loaded) do
		names[modname] = true
	end
	return names
end

local function unload(kept)
	for modname in pairs(package.loaded) do
		if not kept[modname] then
			package.loaded[modname] = nil
		end
	end
end

local function name(program, chunk)
	return program.name or (chunk:match("([^/]+)$"):gsub("%.bpf%.lua$", ""):gsub("%.lua$", ""))
end

---
-- Compiles the program file at `path`. A module an earlier call's body loaded is loaded again, so
-- this call's body reads the kernel scripts it names.
-- @function luaebpf.compile
-- @tparam string path the program file, usually named `<something>.bpf.lua`
-- @tparam[opt] string btffile the kernel's BTF as a raw BTF file, the bytes
--   `/sys/kernel/btf/vmlinux` serves, read once a layout is asked for; that file when absent
-- @tparam[opt] string scripts the directory the body's `require` reads the kernel scripts from, laid
--   out as `/lib/modules/lua` is; that directory when absent
-- @treturn string the BPF ELF object
-- @treturn table a line per call into the kernel Lua runtime the compiler met, in that order,
--   `<file>:<line>: calls the runtime '<name>'`
-- @raise `<file>:<line>: <reason>` for every construct the subset refuses,
--   `<path>: no program declared` when the body hands nothing to a constructor,
--   `<btffile>: <reason>`, `<btffile> carries no BTF header` and `<btffile> is shorter than its
--   BTF header says` when a layout is asked of a file that cannot be read, holds no BTF or is cut
--   short, and `<btffile> is a <order>-endian BTF, for a <order>-endian object` when the BTF a
--   layout was read from is not in the object's byte order
function luaebpf.compile(path, btffile, scripts)
	local chunk = proto.load(path)
	programs.reset()
	maps.reset()
	vmlinux.open(btffile)
	proto.scripts(scripts)
	local host, cpath, kept = package.path, package.cpath, modnames()
	package.path, package.cpath = LIBPATH, "" -- no host module, Lua or C, stands in for a kernel script
	local ok, message = pcall(chunk)
	package.path, package.cpath = host, cpath
	unload(kept)
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
	local object, calls = writer.write(declared, getenv(DROP))
	vmlinux.check(emit.bigendian)
	return object, calls
end

return luaebpf

