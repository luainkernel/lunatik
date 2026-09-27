--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The bpf case of the require_cloneobject test (see require_cloneobject.sh).

local bpf   = require("bpf")
local check = require("tests.runtime.check")

check.clones(bpf.hash("/sys/fs/bpf/test_require_cloneobject_hash"))
check.clones(bpf.queue("/sys/fs/bpf/test_require_cloneobject_queue"))

