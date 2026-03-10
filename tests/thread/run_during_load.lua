--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the spawn-during-module-load regression test (see run_during_load.sh).
--

local runner = require("lunatik.runner")

runner.spawn("tests/thread/dummy")

