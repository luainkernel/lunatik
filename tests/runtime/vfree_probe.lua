--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the vfree test, its probe case (see vfree.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local data   = require("data")
local sizes  = require("tests.runtime.vfree_sizes")
local free   = require("tests.runtime.vfree_blocks")

local buffer = data.new(sizes.vmalloc)

probe.new(systab["personality"], {pre = function() free(buffer) end})

