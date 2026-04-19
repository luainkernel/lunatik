--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Regression: hardirq-class notifier constructor called from a process
-- runtime must fail cleanly. luanotifier_new runs lunatik_newobject before
-- lunatik_checkruntime; when checkruntime errors the object is already
-- allocated with runtime still NULL, and the subsequent __gc -> release
-- would oops on lunatik_putobject(NULL). This script provokes exactly that
-- path; the companion shell test asserts no kernel oops lands in dmesg.
--

local notifier = require("notifier")
notifier.keyboard(function() end)

