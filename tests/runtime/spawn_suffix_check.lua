--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel side of the spawn suffix test, the check (see spawn_suffix.sh).

local lunatik = require("lunatik")

local SCRIPT <const> = "tests/runtime/spawn_suffix"

assert(lunatik._ENV.threads[SCRIPT] ~= nil, "the thread is not registered under the trimmed name")

