--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script that resumes the scx pass test's runtime past its callbacks (see run.sh).

local lunatik = require("lunatik")

local PASS <const> = "tests/scx/pass"
local KEY  <const> = "scx resumed"

local env = lunatik._ENV
local runtime = env.runtimes[PASS]

env[KEY] = runtime:resume()

