--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx re-attach test (see run.sh).

local scx = require("scx")

local function replaced()
end

local function current()
end

scx.attach(replaced)
scx.attach(current)
scx.detach()

