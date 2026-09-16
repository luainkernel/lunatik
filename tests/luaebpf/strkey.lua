--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the compiled c<n> map key test (see strkey.sh).

local map    = require("bpf.map")
local action = require("linux.xdp")

local ROOT   <const> = "/sys/fs/bpf/luaebpf/maps/"
local WIDE   <const> = "c64"
local NARROW <const> = "c16"
local VALUE  <const> = "I4"
local HOST   <const> = "example.com"

local flows <close> = map.hash(ROOT .. "flows", WIDE, VALUE)
flows[HOST] = action.DROP

local shorts <close> = map.hash(ROOT .. "shorts", NARROW, VALUE)
shorts[HOST] = action.TX

print("luaebpf strkey wrote " .. HOST)

