--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the vfree test, its resumed case (see vfree.sh).

local lunatik = require("lunatik")
local data    = require("data")
local sizes   = require("tests.runtime.vfree_sizes")

local BLOCKS <const> = "tests/runtime/vfree_blocks"

local buffer = data.new(sizes.vmalloc)
local runtime <close> = lunatik.runtime(BLOCKS, "hardirq")
runtime:resume(buffer)

