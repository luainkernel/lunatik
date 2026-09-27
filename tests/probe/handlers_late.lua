--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, both handlers added after probe.new (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local prints = require("tests.probe.prints")

local handlers = {}

probe.new(systab["personality"], handlers)

handlers.pre = prints.pre
handlers.post = prints.post

