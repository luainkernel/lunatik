#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the bounds check every packet access carries.
#   - a read one byte past the last, a read at an offset above the ceiling the verifier lets a
#     packet pointer take, a read that lands in the whole ClientHello but past the truncated one,
#     a read at a negative offset the program computed, and a read at an offset past 32 bits whose
#     low 32 name the packet's first byte, which bpf_skb_load_bytes, taking 32, would read: the
#     interpreter raises on each, and the compiled program owes XDP_ABORTED through ctx:packet() on
#     XDP, read between the context's bounds, and TC_ACT_SHOT through skb:data() on TC, read
#     through bpf_skb_load_bytes
#   - every row is declared twice, once with each of two defaults, so the verdict is the error
#     verdict of the program's type whatever default the file named
#   - one run of a read past the end and of one above the ceiling on XDP, and of one past the end
#     and one past 32 bits on TC, each a test of its own, writes "out of bounds" into the trace
#     ring at the read's file and line, once and alone, and counts one stop at that line's place
#     and none at another; so does a read past the end in a program file whose path holds bytes
#     past ASCII, which the line carries as they are
#   - with LUAEBPF_DROP=bounds the object is still written, and the verifier rejects it naming an
#     invalid packet access, which is what says the check is emitted rather than implied
#   - with LUAEBPF_DROP=loadbytes the test of what bpf_skb_load_bytes answers is gone from a TC
#     read, which the verifier takes, and the read one byte past the last keeps the 0 the helper
#     leaves in the frame where the interpreter raises, which is what says the test is emitted. The
#     read above the ceiling keeps 0 too, which says a TC read tests its offset against INT_MAX,
#     the helper's own bound, and not against the ceiling. It is a hook of its own: under the other
#     the object's XDP rows are rejected with it
#
# Usage: sudo bash tests/luaebpf/bounds.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 7

BOUNDS="out of bounds" # luadata_checkbounds, lib/luadata.c

# the line each test of a read logs, the first stops of the object
reads() {
	luaebpf_logs past1 "$(luaebpf_logline bounds "function makers.past" "$BOUNDS")" arp
	luaebpf_logs high1 "$(luaebpf_logline bounds "function makers.high" "$BOUNDS")" arp
	luaebpf_logs skbpast1 "$(luaebpf_logline bounds "function skbmakers.past" "$BOUNDS")" skbarp
	luaebpf_logs skbwrapped1 "$(luaebpf_logline bounds "function skbmakers.wrapped" "$BOUNDS")" skbarp
}

output=$(luaebpf_compile bounds) || { comment "$output"; fail "luaebpf: bounds.bpf.lua did not compile"; }
output=$(luaebpf_loadall bounds) || { comment "$output"; fail "luaebpf: the bounds checks did not verify"; }
ktap_pass "luaebpf: every out-of-bounds row verifies"

luaebpf_logcase "a read out of bounds logs its file and line once, on XDP and on TC" reads

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a bounds row differs from the interpreter"; }
ktap_pass "luaebpf: every out-of-bounds read returns the error verdict of its program's type"

# a program file named in UTF-8, whose line logs the bytes of its path
cat > "$LUAEBPF_WORK/ação.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v = p:getbyte(#p)
	return action.PASS
end, {name = "acao", default = action.PASS})
LUA

# the line the read past the end of ação.bpf.lua logs, the corpus's pins removed first, since the map
# its errors count in takes the name of the corpus's
named() {
	luaebpf_written ação > /dev/null 2>&1 || { echo "ação.bpf.lua did not compile"; return; }
	rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
	luaebpf_loadall ação > /dev/null || { echo "ação.bpf.o did not verify"; return; }
	luaebpf_logs acao "$LUAEBPF_WORK/ação.bpf.lua:6: $BOUNDS"
}

luaebpf_logcase "a read out of bounds logs a path past ASCII as it is" named

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile bounds bounds) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
[ -e "$LUAEBPF_WORK/bounds.bpf.o" ] || fail "luaebpf: the drop hook broke the compile, not the emission"
output=$(luaebpf_loadall bounds 2>&1)
echo "$output" | grep -q "invalid access to packet" \
	|| { comment "$output"; fail "luaebpf: without its bounds check the load was not refused for the packet"; }
ktap_pass "luaebpf: without the bounds check the verifier refuses the packet access"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile bounds loadbytes) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall bounds) || { comment "$output"; fail "luaebpf: without the helper's test the TC rows did not verify"; }
raw=$(luaebpf_keeps skbpast1 skbarp)
[ "$raw" = "0" ] || fail "luaebpf: without the helper's test a TC read past the packet keeps 0, got '$raw'"
ktap_pass "luaebpf: without the test of the helper's answer a TC read past the packet keeps 0"
raw=$(luaebpf_keeps skbhigh1 skbarp)
[ "$raw" = "0" ] || fail "luaebpf: without the helper's test a TC read above the ceiling keeps 0, got '$raw'"
ktap_pass "luaebpf: a TC read above the ceiling reaches bpf_skb_load_bytes"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

