--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe handlers test, a post handler added after probe.new (see handlers.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local function pre()
	print("probe handlers: pre")
end

local function post()
	print("probe handlers: post")
end

local handlers = {pre = pre}

probe.new(systab["personality"], handlers)

handlers.post = post

