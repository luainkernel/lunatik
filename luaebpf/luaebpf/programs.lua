--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Where a program constructor leaves what a program file declared.
--
-- The file body runs once, on the host, and hands its functions to `bpf.xdp` and its peers;
-- `luaebpf.compile` reads them back from here, in declaration order. Each carries the ELF
-- section its entry belongs in, which is how libbpf reads the program type back.
-- @module luaebpf.programs

local insert = table.insert

local declared = {}

local programs = {}

---
-- Forgets what a previous compilation declared.
-- @function luaebpf.programs.reset
function programs.reset()
	declared = {}
end

---
-- Records one program.
-- @function luaebpf.programs.declare
-- @tparam table program `{section, fn, default, name, context, kfunc}`
-- @treturn table the same program
function programs.declare(program)
	insert(declared, program)
	return program
end

---
-- The programs the file body declared, in order.
-- @function luaebpf.programs.declared
-- @treturn table
function programs.declared()
	return declared
end

return programs

