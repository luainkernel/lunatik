--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luac test (see run.sh): a text script requiring a compiled library.

local lib = require("tests.luac.lib_bc")

assert(lib.answer() == 42)
print("luac: require of a compiled library")

