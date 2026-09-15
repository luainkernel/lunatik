--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto context test (see context.sh).
-- Holds one object of each refused kind alive so the harness can see which
-- modules back their algorithms.

local crypto = require("crypto")

HELD = {crypto.shash("sha256")} -- global: the references are what raise the modules' refcounts

local ok, comp = pcall(crypto.comp, "lz4") -- the binding has no comp from 6.15 on, and lz4 may not be built
if ok then
	table.insert(HELD, comp)
end

