#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/filter deployed as the tree ships it: `lunatik run` compiles nothing here, it
# loads the object `make install` built and attaches it to the device named on the command line.
#   - the kernel-side fixture builds two ClientHello frames, one naming the blocked host and one
#     naming another, puts them on filter1 with a raw socket and taps filter0 with a second one
#     under a bounded receive, printing which of the two it saw. It matches on the host name's
#     own bytes, so whatever else the machine puts on the pair is ignored rather than silenced
#   - with nothing attached both frames reach the tap, which is what says the tap is evidence of
#     a drop rather than of a frame that never arrived
#   - with the filter deployed the blocked name's frame does not reach the tap and the other one
#     does: generic XDP leaves by `goto out` before the ptype_all taps and the native path drops
#     before napi_gro_receive, so a frame XDP dropped is one the tap never sees
#   - the blocklist map holds one hit under the blocked name and no entry at all under the other,
#     which says the program parsed the name rather than dropping for some other reason
#   - the CLI's stop leaves no pin root, no runtime and nothing on filter0
# Every measurement is taken before the first check and the example is stopped before them all,
# so a failing row leaves the next case nothing. Skips where the object is not installed, which
# is what a kernel publishing no bpf_xdp_load_bytes leaves behind.
#
# Usage: sudo bash tests/luaebpf/example_filter.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/example_filter
OBJECT=/lib/modules/lua/$LUAEBPF_FILTER.bpf.o
MAP=$LUAEBPF_DEPLOY/$LUAEBPF_FILTER/blocked
BLOCKED="ebpf.io"
ALLOWED="pass.example"
# the counter examples/filter/sni.bpf.lua leaves under a name it dropped once, as bpftool prints
# an I8 value, and the width of the c64 key it is held under
HIT="01 00 00 00 00 00 00 00"
KEYWIDTH=64
PLAN=4

luaebpf_start "$PLAN"

[ -r "$OBJECT" ] || luaebpf_skipall "$PLAN" "$OBJECT is not installed"
luaebpf_device "$LUAEBPF_FILTERDEV" "$LUAEBPF_FILTERPEER" \
	|| luaebpf_skipall "$PLAN" "the case could not create $LUAEBPF_FILTERDEV"

# one run of the fixture, answering the two lines it printed; its own error, if it had one, goes
# into that answer, where the comparison shows it
tapped() {
	local output
	mark_dmesg
	output=$(lunatik run "$SCRIPT" 2>&1)
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	[ -z "$output" ] || echo "the fixture said: $output"
	dmesg_since | grep -oP 'luaebpf filter: \K[a-z.]+ [a-z]+' | sort | tr '\n' ' '
}

# what the map holds under a name, as bpftool prints it, or "absent"; a key of sixty-four bytes
# makes it print the value on its own lines rather than beside the key
held() {
	local name="$1" key= i out
	for ((i = 0; i < KEYWIDTH; i++)); do
		if [ "$i" -lt "${#name}" ]; then
			key="$key $(printf '%d' "'${name:i:1}")"
		else
			key="$key 0"
		fi
	done
	out=$(bpftool map lookup pinned "$MAP" key $key 2>&1) || { echo absent; return; }
	echo "$out" | sed -n '/^value:/,$p' | tail -n +2 | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//; s/ *$//'
}

control=$(tapped)

deployed=$(lunatik run "$LUAEBPF_FILTER" dev="$LUAEBPF_FILTERDEV" 2>&1)
enforced=$(tapped)
dropped=$(held "$BLOCKED")
passed=$(held "$ALLOWED")

lunatik stop "$LUAEBPF_FILTER" > /dev/null 2>&1
left=$(luaebpf_residue "$LUAEBPF_FILTER" "$LUAEBPF_FILTERDEV")

[ -z "$deployed" ] || { comment "$deployed"; fail "luaebpf: the example did not deploy"; }
[ "$control" = "$BLOCKED seen $ALLOWED seen " ] \
	|| { comment "$control"; fail "luaebpf: the tap saw neither frame with nothing attached"; }
ktap_pass "luaebpf: both ClientHellos reach the tap with nothing attached"

[ "$enforced" = "$BLOCKED absent $ALLOWED seen " ] \
	|| { comment "$enforced"; fail "luaebpf: the filter dropped '$enforced'"; }
ktap_pass "luaebpf: the deployed filter drops the blocked name and passes the other"

[ "$dropped" = "$HIT" ] || fail "luaebpf: the map holds '$dropped' under $BLOCKED, not '$HIT'"
[ "$passed" = absent ] || fail "luaebpf: the map holds '$passed' under $ALLOWED, which it never blocked"
ktap_pass "luaebpf: the blocklist counts the name the program parsed and no other"

[ -z "$left" ] || fail "luaebpf: the stop left$left"
ktap_pass "luaebpf: the CLI's stop takes the example off the device and out of the pin root"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

