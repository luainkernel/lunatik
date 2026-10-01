--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel side of the runner context test (see run_context.sh).

local socket = require("socket")
local sk     = require("linux.socket")

socket.new(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP):close()

