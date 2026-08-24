--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luac test (see run.sh): load() with mode "t" rejects a compiled chunk.

local f = assert(io.open("/lib/modules/lua/tests/luac/hello_bc.lua", "rb"))
local chunk = f:read("a")
f:close()

local fn, err = load(chunk, "=hello", "t")
assert(fn == nil and err:find("binary chunk", 1, true), err)
assert(load(chunk, "=hello", "b"))
print("luac: text-only load rejects bytecode")

