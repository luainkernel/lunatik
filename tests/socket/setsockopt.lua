--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket setsockopt test (see setsockopt.sh).

local socket = require("socket")
local struct = require("struct")
local sk     = require("linux.socket")

local timeval    = struct(sk.layout.timeval)
local TIMEOUT_MS = 100
local RCVBUF     = 32768

local s = socket.new(sk.af.NETLINK, sk.sock.RAW, 0)

-- integer value: the common int payload
s:setsockopt(sk.sol.SOCKET, sk.so.RCVBUF, RCVBUF)
print("socket setsockopt: integer option set")

-- string value: a packed struct payload; no data ever arrives, so a bounded
-- receive must return (raise), not hang
s:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT_MS * 1000))
local ok = pcall(s.receive, s, 16)
s:close()
assert(not ok, "receive should have timed out")
print("socket setsockopt: bounded receive returned")

