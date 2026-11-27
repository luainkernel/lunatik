--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the btfview case over a struct of crossing bitfields (see btfview.sh).

require("luaebpf.emit").bigendian = false

local vmlinux = require("bpf.vmlinux")
local xdp     = require("bpf.xdp")
local action  = require("linux.xdp").action

local out = assert(io.open("crossing.txt", "w"))
for _, field in ipairs(vmlinux.layout("crossing").bitfields) do
	out:write(field.name, " ", field.offset, " ", field.size, " ", tostring(field.signed), " ", field.shift, " ",
		field.mask, "\n")
end
out:close()

return xdp.program(function(_) return action.PASS end, {default = action.PASS})

