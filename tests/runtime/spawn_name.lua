--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel side of the spawn name test, the check (see spawn_name.sh).

local lunatik = require("lunatik")

local SCRIPT <const> = "tests/runtime/my_body"
local NAME <const> = "runtime/my_body"

local comm = lunatik._ENV.threads[SCRIPT]:task():comm()
assert(comm == NAME, "the thread is named " .. comm)

