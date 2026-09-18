--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side peer for the plain tunnel test (see plain.sh).

local pair = require("tests.tunnel.pair")

-- global, so the far ends outlive the chunk: the shell closes them by stopping
-- this runtime, which is the end-of-file stimulus the relay reads
ends = {pair.connectpair()}

local a, b = ends[1], ends[2]
print("tunnel plain: B read " .. pair.through(a, b, pair.atob))
print("tunnel plain: A read " .. pair.through(b, a, pair.btoa))

