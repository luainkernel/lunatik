--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bigtable_free test (see bigtable_free.sh).
-- Holds a table whose private is large enough to be vmalloc-backed in a global;
-- the harness measures it, then frees it by stopping the runtime.

local BIG_BUCKETS <const> = 1 << 22 -- ~32 MiB of buckets, past the kmalloc order

BIGTABLE = require("rcu").table(BIG_BUCKETS)
BIGTABLE["probe"] = true
