--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Declares types into classes, for the types case (see types.sh).

local frame = require("luaebpf.emit.frame")
local classes, typenames = frame.classes, frame.typenames
local A = frame.type("a", "word", "untested")
local B = frame.type("b")
assert(A ~= B and A & B == 0, "two types share a bit")
assert(typenames[A] == "a" and typenames[B] == "b", "a type is not recorded under its name")
assert(classes.word & A ~= 0 and classes.untested & A ~= 0, "a type is missing from a class it declared")
assert(classes.proxy & A == 0, "a type joined a class it did not declare")
assert((classes.word | classes.proxy | classes.untested) & B == 0, "a type declared into no class joined one")

