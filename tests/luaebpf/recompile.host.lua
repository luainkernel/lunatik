--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Compiles scripts.bpf.lua three times in one process, for the scripts case (see scripts.sh).

local luaebpf = require("luaebpf")

local program, scripts, broken, object = table.unpack(arg)
luaebpf.compile(program)
local ok, err = pcall(luaebpf.compile, program, nil, broken)
assert(not ok and err:find("module 'class' not found", 1, true),
	"the compile of a directory lacking class gave: " .. tostring(err))
local file = assert(io.open(object, "wb"))
assert(file:write((luaebpf.compile(program, nil, scripts))))
assert(file:close())

