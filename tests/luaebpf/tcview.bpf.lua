--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the view case reading a field of two bytes in TC (see view.sh).

require("luaebpf.emit").unaligned = false
local struct  = require("struct")
local vmlinux = require("bpf.vmlinux")
local tc      = require("bpf.tc")
local action  = require("linux.tc").action

local iphdr = struct(vmlinux.layout("iphdr"))

return tc.program(function(skb)
	local p = skb:data()
	local ip = iphdr:view(p, 14)
	local v = ip.tot_len
	return v
end, {default = action.OK})

