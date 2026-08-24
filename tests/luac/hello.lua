--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luac test (see run.sh): a compiled chunk runs with integer semantics.

local linux = require("linux")

assert(7 / 2 == 3, "integer division")
assert(type(linux.time()) == "number")
print("luac: hello from bytecode")

