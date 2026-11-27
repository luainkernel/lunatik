--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Writes an XDP program assembled by hand, for the object case (see object.sh).

local insn = require("luaebpf.insn")
local elf  = require("luaebpf.elf")
local btf  = require("luaebpf.btf")

local reg = insn.reg
local bigendian = arg[2] == "big"

local code = insn.new()
code:source(1)
code:set(reg.R0, 1)
local skip = code:label()
code:jump(skip)
code:source(2)
code:set(reg.R0, 0)
code:place(skip)
code:source(3)
code:set(reg.R1, 0x100000002)
code:exit()

local object, types = elf.new(bigendian), btf.new(bigendian)
object:section{name = "xdp", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.EXEC,
	data = code:pack(bigendian), align = 8}
object:symbol{name = "prog", section = "xdp", value = 0, size = code:len() * insn.SIZE, bind = elf.bind.GLOBAL,
	type = elf.type.FUNC}
object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.WRITE,
	data = "Dual MIT/GPL\0", align = 1}

local texts = {"r0 = 1", "r0 = 0", "r1 = 0x100000002"}
local func = types:func("prog", btf.linkage.GLOBAL, {result = types.int, params = {types.long}})
local file = types:string("object.sh")
local lines, previous = {}, nil
for i, line in ipairs(code:sourcelines()) do
	if line ~= previous then
		table.insert(lines, types:lineinfo((i - 1) * insn.SIZE, file, types:string(texts[line]), line, 1))
		previous = line
	end
end
local ext = types:ext({{name = "xdp", funcs = {types:funcinfo(0, func)}, lines = lines}})
object:section{name = ".BTF", type = elf.section.PROGBITS, flags = 0, data = types:pack(), align = 4}
object:section{name = ".BTF.ext", type = elf.section.PROGBITS, flags = 0, data = ext, align = 4}

local out = assert(io.open(arg[1], "wb"))
assert(out:write(object:pack()))
assert(out:close())

