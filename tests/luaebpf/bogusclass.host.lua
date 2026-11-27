--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Declares a type into a class the frame does not read, for the types case (see types.sh).

local frame = require("luaebpf.emit.frame")
frame.type("x", "bogus")

