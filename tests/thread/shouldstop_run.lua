--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the shouldstop() run context test (see shouldstop.sh).
--

local thread = require("thread")

assert(thread.shouldstop() == false)

