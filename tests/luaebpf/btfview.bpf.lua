--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the btfview case (see btfview.sh).

local corpus  = require("tests.luaebpf.corpus")
local struct  = require("struct")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")
local action  = require("linux.xdp").action
local eth     = require("linux.eth")

local WORD <const> = 4 -- bytes in a unit of iphdr's ihl and of tcphdr's doff

-- a bitfield's shift goes apart from its layout, being what the BTF's byte order changes
local out, shifts = assert(io.open("layout.txt", "w")), assert(io.open("shift.txt", "w"))
for _, what in ipairs({"xdp_md", "__sk_buff", "iphdr", "tcphdr", "flowi_tunnel"}) do
	local layout = vmlinux.layout(what)
	out:write("size\t", what, "\t", layout.size, "\n")
	for _, field in ipairs(layout.fields) do
		out:write("field\t", what, "\t", field.name, "\t", field.offset, "\t", field.size, "\t",
			tostring(field.bigendian == true), "\n")
	end
	for _, field in ipairs(layout.bitfields) do
		out:write("bitfield\t", what, "\t", field.name, "\t", field.offset, "\t", field.size, "\t", field.mask, "\n")
		shifts:write(what, "\t", field.name, "\t", field.shift, "\n")
	end
end
local ok, message = pcall(vmlinux.layout, "a_struct_no_kernel_publishes")
out:write("missing\t", tostring(ok), "\t", message, "\n")
out:close()
shifts:close()

-- what views of the kernel's own iphdr and tcphdr read off the packets of the corpus that carry both,
-- the TCP header found past the IPv4 one by its ihl
local iphdr, tcphdr = struct(vmlinux.layout("iphdr")), struct(vmlinux.layout("tcphdr"))
local packets = corpus.packets()
local views = assert(io.open("view.txt", "w"))
for _, name in ipairs({"syn", "tls"}) do
	local p = packets[name]:packet()
	local ip = iphdr:view(p, eth.HLEN)
	local tcp = tcphdr:view(p, eth.HLEN + ip.ihl * WORD)
	views:write(name, " ", ip.version, " ", ip.ihl, " ", ip.tot_len, " ", ip.protocol, " ", tcp.dest, " ",
		tcp.doff, " ", tcp.syn, " ", tcp.ack, " ", tcp.psh, "\n")
end
views:close()

return xdp.program(function(_) return action.PASS end, {default = action.PASS})

