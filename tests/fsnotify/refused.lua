--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify context test (see context.sh).

local fsnotify = require("fsnotify")

local function report(mask)
	print(mask)
end

fsnotify.watch(report)

