--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf softirq-runtime test (see run.sh).

local map = require("bpf").map

local m = map("/sys/fs/bpf/test_map")
assert(m:update("sfq", "irq"), "softirq runtime update failed")
assert(m:lookup("sfq") == "irq", "softirq runtime lookup mismatch")
assert(m:delete("sfq"), "softirq runtime delete failed")
m:close()

