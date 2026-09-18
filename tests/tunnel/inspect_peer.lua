--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side peer for the transform test (see inspect.sh).

local pair   = require("tests.tunnel.pair")
local struct = require("struct")
local sk     = require("linux.socket")

local timeval = struct(sk.layout.timeval)

-- the relay yields 10 ms when idle, so a read that waits this long and still
-- sees nothing saw a payload the transform dropped
local MISSING <const> = 500 * 1000

-- global, so the far ends outlive the chunk
ends = {pair.connectpair()}

local a, b = ends[1], ends[2]
print("tunnel inspect: B read " .. pair.through(a, b, pair.atob))
print("tunnel inspect: A read " .. pair.through(b, a, pair.btoa))

-- the dropped payload leaves nothing to read, and the two round trips above say
-- the relay was carrying bytes before it
b:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, MISSING))
a:send(pair.dropped)
local ok, got = pcall(b.receiverecord, b, pair.readmax)
print("tunnel inspect: B read " .. (ok and got or "nothing (" .. tostring(got) .. ")"))

