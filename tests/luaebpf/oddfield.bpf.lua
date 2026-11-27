--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the struct case with a field of three bytes (see struct.sh).

local map = require("bpf.map")
local struct = require("struct")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local codec = struct{size = 4, fields = {{name = "n", offset = 0, size = 3, signed = false}}}
map.hash("records", {key = "I4", value = codec, entries = 8})

return xdp.program(function(_)
	return 0
end, {default = action.PASS})

