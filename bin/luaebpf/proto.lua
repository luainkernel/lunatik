--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Loads a file as the kernel's Lua compiles it, and hands the translator a function's prototype.
--
-- `lunatic` compiles the file, and the CLI's Lua loads the chunk rewritten in its own numbering, so
-- the program file's body runs the kernel's bytecode and computes as the kernel would, and a
-- function it hands over is that bytecode, read back from its own `string.dump`. A module the body
-- requires from the kernel scripts loads the same way, through the searcher this module puts last
-- in `package.searchers`, from `/lib/modules/lua` or the directory `luaebpf.proto.scripts` names.
-- @module luaebpf.proto

local kernel = require("luaebpf.bytecode.kernel")
local host   = require("luaebpf.bytecode.host")
local undump = require("luaebpf.undump")

local format     = string.format
local dump       = string.dump
local insert     = table.insert
local getinfo    = debug.getinfo
local popen      = io.popen
local searchpath = package.searchpath

local LUNATIC   <const> = "lunatic -o - -- "
local SCRIPTS   <const> = "/lib/modules/lua" -- the kernel's LUA_ROOT
local MODULES   <const> = "%s/?.lua;%s/?/init.lua" -- the kernel's LUA_PATH_DEFAULT, under a root
local ELSEWHERE <const> = "a compiled function is defined in the program file or a kernel script it requires, " ..
	"installed as source"

local proto = {}

---
-- The opcode numbers of the kernel's Lua, by name; a name the kernel's Lua lacks raises.
-- @table luaebpf.proto.opcodes
proto.opcodes = setmetatable({}, {__index = function(_, name)
	error(format("luaebpf.proto: no opcode '%s' in the kernel's Lua", name), 2)
end})
for name, opcode in pairs(kernel.opcodes) do
	rawset(proto.opcodes, name, opcode.op)
end

local tokernel = {}
for name, opcode in pairs(host.opcodes) do
	local own = kernel.opcodes[name]
	tokernel[opcode.op] = own and own.op
end

local loaded = {}
local root = SCRIPTS

local function quote(word)
	return "'" .. word:gsub("'", "'\\''") .. "'"
end

---
-- Compiles the file at `path` with `lunatic` and loads the chunk in the CLI's Lua.
-- @function luaebpf.proto.load
-- @tparam string path a Lua file, as source or as a chunk `lunatic` wrote
-- @treturn function the chunk's main function
-- @raise `<path>: lunatic could not compile it`, after `lunatic`'s own message, or the error
--   `load` gives a chunk it refuses
function proto.load(path)
	local pipe = popen(LUNATIC .. quote(path), "r")
	local bytes = pipe:read("a")
	if not pipe:close() then
		error(format("%s: lunatic could not compile it", path), 0)
	end
	local chunk, err = load(undump.rewrite(bytes, path, kernel, host), "=" .. path, "b")
	if chunk == nil then
		error(err, 0)
	end
	local source = getinfo(chunk, "S").source
	if source:sub(1, 1) == "@" then -- a stripped chunk names no file and no line to refuse by
		loaded[source] = true
	end
	return chunk
end

---
-- Reads the kernel scripts a program file's body requires from under `dir` from then on, laid out
-- as the kernel's `require` reads `/lib/modules/lua`; a module `dir` lacks is not found.
-- @function luaebpf.proto.scripts
-- @tparam[opt] string dir the directory, `/lib/modules/lua` when absent
function proto.scripts(dir)
	root = dir or SCRIPTS
end

local function search(name)
	local path, err = searchpath(name, format(MODULES, root, root))
	if path == nil then
		return err
	end
	return proto.load(path), path
end
insert(package.searchers, search) -- last: a module package.path finds is the CLI's Lua and shadows the kernel's

local function renumber(p)
	for _, ins in ipairs(p.code) do
		ins.op = tokernel[ins.op]
	end
	for _, nested in ipairs(p.protos) do
		renumber(nested)
	end
	return p
end

---
-- The prototype of `fn`, a function of a file `luaebpf.proto.load` loaded, its opcodes numbered
-- as the kernel's Lua numbers them.
-- @function luaebpf.proto.read
-- @tparam function fn a Lua function
-- @treturn table `{source, linedefined, lastlinedefined, numparams, isvararg, maxstacksize, nk,
--   code, lines, k, upvalues, protos}`, as `luaebpf.undump.read` returns it
-- @raise `<file>:<line>: a compiled function is defined in the program file or a kernel script it
--   requires, installed as source`
function proto.read(fn)
	local info = getinfo(fn, "S")
	if info.what == "C" then
		error("bad argument #1 to 'read' (Lua function expected)", 2)
	end
	if not loaded[info.source] then
		error(format("%s:%d: %s", info.short_src, info.linedefined, ELSEWHERE), 0)
	end
	return renumber(undump.read(dump(fn), format("%s:%d", info.source:sub(2), info.linedefined), host))
end

return proto

