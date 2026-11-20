#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests a view of a struct over the packet, `codec:view(p, at)` in a compiled function, which reads a
# field by name as one packet read at the view's offset plus the field's.
#   - views of the kernel's own ethhdr, iphdr and tcphdr, laid out by bpf.vmlinux, over every
#     packet of the corpus through ctx:packet() and through skb:data(), against the interpreted twin,
#     lib/struct.lua's codec:view over the same bytes: h_proto and tot_len, which the layout marks
#     bigendian, ttl, a byte, check, a __sum16 read in the kernel's order, version and ihl, bitfields
#     of a byte at two shifts, and the TCP header found past the IPv4 one by ihl, an offset the
#     program computes: dest and seq, big-endian of two and four bytes, doff, a bitfield of a two-byte
#     load, and psh, a bit. A wrong offset, width, order, shift or mask changes the number
#   - a codec the body writes by hand over the source address, whose first byte has its high bit set:
#     a signed byte, a signed big-endian field, a signed native one, a signed bitfield and a big-endian
#     field of eight bytes, so a sign extension or a swap that is missing changes the number
#   - each view is made and read in a function the program calls with the packet, and in the
#     program's own frame through the context: a read past the end of the packet, the TCP header's
#     doff on the ICMP echo, stops the program at that field, after what an earlier field of the same
#     view kept, as the twin raises there, and one run of it writes "out of bounds" into the trace
#     ring at the line of the read, the callee's, once and alone, on XDP and on TC, and counts one
#     stop at that line's place and none at another; and a view each
#     arm of a branch makes of the one struct, at an offset of its own, is read where the arms meet,
#     by the struct both arms agree on
#   - a view made with no offset, where an earlier call left a number in the register the offset
#     would take, over the context, at an offset that is not a number, and another method of a codec
#     are refused; so are a field the layout lacks, a write to a field, an index into a view, a method
#     called on it, a view passed to a function or returned, one that may be nil, one two structs
#     merge into, a read in a function that assigned the parameter its packet came in, whatever copy
#     of it another register holds, and a field whose width no eBPF load covers
#   - on a kernel without efficient unaligned access an XDP field wider than a byte is refused, a
#     bitfield whose load is two bytes among them, and a byte field and a bitfield of a byte are not,
#     the program file's body setting the answer lunatik.config gives such a kernel, as packet.sh does;
#     a TC field that wide compiles, since bpf_skb_load_bytes copies its bytes into the frame
#
# Usage: sudo bash tests/luaebpf/view.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 20

BOUNDS="out of bounds" # luadata_checkbounds, lib/luadata.c

# the line a field read past the end logs, in the function that reads it, the first stops of the object
fields() {
	luaebpf_logs doff2 "$(luaebpf_logline view "function reads.doff" "$BOUNDS")" icmp
	luaebpf_logs skbdoff2 "$(luaebpf_logline view "function reads.doff" "$BOUNDS")" skbicmp
}

output=$(luaebpf_compile view) || { comment "$output"; fail "luaebpf: view.bpf.lua did not compile"; }
output=$(luaebpf_loadall view) || { comment "$output"; fail "luaebpf: the view reads did not verify"; }
ktap_pass "luaebpf: every view row verifies"

luaebpf_logcase "a view field read past the packet logs its file and line once, on XDP and on TC" fields

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a view read differs"; }
ktap_pass "luaebpf: every field a view reads answers what the interpreted view reads off the same bytes"

# every row is one compiled function over the context with the kernel's iphdr at hand, so only the body
# and what the file declares before it differ
row() {
	local name="$1" line="$2" message="$3" body="$4" preamble="${5:-}"
	{
		echo 'local struct = require("struct")'
		echo 'local vmlinux = require("bpf.vmlinux")'
		echo 'local xdp = require("bpf.xdp")'
		echo 'local action = require("linux.xdp").action'
		echo 'local iphdr = struct(vmlinux.layout("iphdr"))'
		echo "$preamble"
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo "$body"
		echo 'end, {default = action.PASS})'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$line: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

view=$'\tlocal p = ctx:packet()\n\tlocal ip = iphdr:view(p, 14)\n'
# the read on line 10 leaves its second argument where view's offset would be: unchecked, the view starts there
row noargs 11 "'view' takes the packet and an offset" \
	$'\tlocal p = ctx:packet()\n\tp:getbyte(3, 4)\n\tlocal ip = iphdr:view(p)\n\treturn 0'
row notpacket 9 "'view' takes the packet, not a context" $'\tlocal ip = iphdr:view(ctx, 14)\n\treturn 0'
row notoffset 10 "'view' takes an offset, not a boolean" \
	$'\tlocal p = ctx:packet()\n\tlocal ip = iphdr:view(p, true)\n\treturn 0'
row codecmethod 9 "a codec's 'pack' cannot be called in a compiled function" $'\tlocal s = iphdr:pack(1)\n\treturn 0'
row nofield 11 "a view has no field 'missing'" "$view"$'\treturn ip.missing'
row fieldwrite 11 "a table cannot be written in a compiled function" "$view"$'\tip.ttl = 1\n\treturn 0'
row index 11 "'a table' is read from a value the compiler cannot resolve" "$view"$'\treturn ip[1]'
row viewmethod 11 "the view has no method 'getbyte'" "$view"$'\tlocal v = ip:getbyte(0)\n\treturn v'
row argument 11 "argument #1 is a view, and a compiled call passes numbers and packets" \
	"$view"$'\tlocal v = ttl(ip)\n\treturn v' 'local function ttl(h) return h.ttl end'
row returned 11 "a view has no value in the kernel here" "$view"$'\treturn ip'
row maybenil 12 "'a table' is read from a value the compiler cannot resolve" \
	$'\tlocal p = ctx:packet()\n\tlocal ip\n\tif p:getbyte(0) == 1 then ip = iphdr:view(p, 14) end\n\treturn ip.ttl'
merged=$'\tlocal p = ctx:packet()\n\tlocal h\n\tif p:getbyte(0) == 1 then h = iphdr:view(p, 14) else h = tcp:view(p, 14) end'
row twostructs 12 "a view here is of more than one struct" "$merged"$'\n\treturn h.ttl' \
	'local tcp = struct(vmlinux.layout("tcphdr"))'
# the callee assigns the parameter its packet came in, and the copy view's call left past it is no holder
row nopacket 6 "a view is read through the context or a packet, which no parameter of the function holds here" \
	$'\tlocal p = ctx:packet()\n\tlocal v = ttl(p)\n\treturn v' \
	'local function ttl(p) local ip = iphdr:view(p, 14) p = nil return ip.ttl end'
row oddwidth 12 "a view reads 1, 2, 4 or 8 bytes at a time, not 3" "$view"$'\tlocal o = odd:view(p, 0)\n\treturn o.n' \
	'local odd = struct{size = 4, fields = {{name = "n", offset = 0, size = 3, signed = false}}}'

# the byte field on line 11 and the bitfield of a byte on line 12 compile; tot_len, on line 13, is refused
row unaligned 13 "field 'tot_len' reads more than a byte, and this kernel lacks efficient unaligned access" \
	"$view"$'\tlocal a = ip.ttl\n\tlocal b = ip.ihl\n\tlocal c = ip.tot_len\n\treturn a + b + c' \
	'require("luaebpf.emit").unaligned = false'
row unalignedbits 12 "field 'doff' reads more than a byte, and this kernel lacks efficient unaligned access" \
	"$view"$'\tlocal t = tcp:view(p, 34)\n\tlocal d = t.doff\n\treturn d' \
	'require("luaebpf.emit").unaligned = false local tcp = struct(vmlinux.layout("tcphdr"))'

cat > "$LUAEBPF_WORK/tcwide.bpf.lua" <<'LUA'
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
LUA
output=$(luaebpf_written tcwide 2>&1) \
	|| { comment "$output"; fail "luaebpf: a TC view field wider than a byte is refused without efficient unaligned access"; }
ktap_pass "luaebpf: a TC view field wider than a byte compiles without efficient unaligned access"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

