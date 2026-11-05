--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side packet socket for the tc shared case (see test_tc.sh).

local raw   = require("socket.raw")
local linux = require("linux")
local eth   = require("linux.eth").proto

local IFNAME <const> = "lunatik0" -- IFACE in test_tc.sh

tap = raw.new(eth.ALL, linux.ifindex(IFNAME)) -- a global: the frames it takes stay queued until the script stops

