--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto context test (see context.sh).
-- Holds one object of each refused kind alive so the harness can see which
-- modules back their algorithms.

local crypto = require("crypto")
local insert = table.insert

HELD = {} -- global: the references are what raise the modules' refcounts

local function hold(new, algname)
	local ok, object = pcall(new, algname)
	if ok then
		insert(HELD, object)
	end
end

hold(crypto.shash, "sha256") -- the kernel may serve no sha256
hold(crypto.comp, "lz4") -- the binding has no comp from 6.15 on, and lz4 may not be built
hold(crypto.acompress, "lz4") -- lz4 may not be built
hold(crypto.sig, "ecdsa-nist-p256") -- ECDSA may not be built

