--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto large test's comp case (see large.sh).

local crypto = require("crypto")
local lib = require("tests.lib")
local test = lib.test
local sizes = require("tests.crypto.large_sizes")
local refused = require("tests.crypto.refused")

local rep, sub = string.rep, string.sub
local LZ4 <const> = "lz4"
local BLOCK <const> = 16
local ENOMEM <const> = "not enough memory"

local page = sizes.page
local SCOMP_MAX <const> = 128 * 1024 -- the input scomp takes up to 6.14
local spanning = sub(rep("a", page) .. rep("b", page) .. rep("c", BLOCK), 1, SCOMP_MAX)
local oversized = rep("x", sizes.kmalloc + page)

-- the algorithm the case allocates, before it runs, so large.sh skips the test where the kernel lacks one
lib.alloc(crypto.comp, LZ4)

test("COMP LZ4 data spanning pages round-trips", function()
	local c = crypto.comp(LZ4)
	local compressed = c:compress(spanning, 2 * #spanning)
	assert(#compressed < #spanning, "compressed data is not shorter than the original")
	assert(c:decompress(compressed, #spanning) == spanning, "round-trip mismatch")
end)

test("COMP data past KMALLOC_MAX_SIZE", function()
	local c = crypto.comp(LZ4)
	refused(ENOMEM, "compress", c.compress, c, oversized, page)
	refused(ENOMEM, "decompress", c.decompress, c, oversized, page)
	refused(ENOMEM, "compress output", c.compress, c, "x", #oversized)
	refused(ENOMEM, "decompress output", c.decompress, c, "x", #oversized)
end)

