--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto context test (see context.sh).
-- Holds one shash alive so the harness can see which module backs sha256.

local crypto = require("crypto")

HELD = crypto.shash("sha256") -- global: the reference is what raises the module's refcount

