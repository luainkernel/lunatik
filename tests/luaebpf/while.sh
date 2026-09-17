#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the loops a numeric `for` does not cover.
#   - a `while` and a `repeat` whose limit the program computes, a `break` out of the body and a
#     nested pair: each takes a may_goto header at the jump that closes it, verifies, and
#     terminates with the interpreter's answer. The verifier's own log is what shows the header,
#     since the kernel rewrites it into a loop counter on the way in
#   - a `while` whose condition the compiler settles takes no back edge and no header, which the
#     counter the kernel writes into the frame is what says: the bounded rows carry it and that
#     one does not
#   - with LUAEBPF_DROP=maygoto the header is gone and the verifier refuses the loop it cannot
#     bound: the row that carries it takes its limit from the context, which is a word the
#     verifier knows nothing about, where every other limit it could simulate its way through
#   - with LUAEBPF_PROBE offering the compiler no loop form the backward jump is refused with its
#     message and line, which is the row a kernel below v6.9 takes
#   - a loop nothing leaves is refused: the header names the instruction after its own back edge,
#     and there is nothing there to reach
# The case reads the may_goto lowering, so it skips where the compiler takes the iterators instead
# or bounds no loop at all: iter.sh and forvar.sh are the cases those kernels run.
#
# Usage: sudo bash tests/luaebpf/while.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

BUDGET=8388608 # BPF_MAX_LOOPS, which the kernel writes into the frame for a may_goto

ROWS=6

luaebpf_start "$ROWS"

# the may_goto lowering is what this case reads: a kernel the compiler takes the iterators on is
# iter.sh's, and one it bounds no loop on is forvar.sh's refusal row
output=$(luaebpf_compile while)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "which this kernel lacks" \
		|| { comment "$output"; fail "luaebpf: while.bpf.lua did not compile"; }
	luaebpf_skipall "$ROWS" "the compiler bounds no loop on this kernel"
fi
if bpftool btf dump file "$LUAEBPF_WORK/while.bpf.o" format raw 2>/dev/null | grep -q bpf_iter_num; then
	luaebpf_skipall "$ROWS" "the compiler takes the iterators here, not may_goto"
fi
log=$(luaebpf_verbose while)
[ -e "$LUAEBPF_PINS/nested2" ] || { comment "$log"; fail "luaebpf: the loops did not verify"; }
echo "$log" | grep -q "may_goto" \
	|| fail "luaebpf: a loop the compiler cannot bound took no may_goto header"
ktap_pass "luaebpf: every 'while' and 'repeat' takes a may_goto header and verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a loop differs from the interpreter"; }
ktap_pass "luaebpf: every loop terminates with the interpreter's answer"

# the counter the kernel patches a may_goto into, which is what a program carrying one shows
counted() {
	bpftool prog dump xlated pinned "$LUAEBPF_PINS/$1" 2>&1 | grep -c "$BUDGET"
}

[ "$(counted whilelimit2)" -ge 1 ] || fail "luaebpf: a computed limit carries no loop counter"
[ "$(counted nested2)" -ge 1 ] || fail "luaebpf: a nested pair carries no loop counter"
[ "$(counted folded1)" -eq 0 ] || fail "luaebpf: a condition the compiler settled still took a header"
ktap_pass "luaebpf: a condition the compiler settles takes no back edge and no header"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile while maygoto) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall while 2>&1)
echo "$output" | grep -q "prog 'ctxlimit': failed to load" \
	|| { comment "$output"; fail "luaebpf: without its header the loop was not refused"; }
ktap_pass "luaebpf: without the may_goto header the verifier rejects the loop"

# every row is one compiled function whose loop the compiler refuses
row() {
	local name="$1" message="$2" body="$3" probe="${4:-}"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'local one = 1'
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message" "$probe")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row noform "noform.bpf.lua:10: a loop the compiler cannot bound needs may_goto, which this kernel lacks" \
	$'\tlocal s = 0\n\tlocal i = 1\n\twhile i <= one + 1 do\n\t\ts = s + i\n\t\ti = i + 1\n\tend\n\treturn s' \
	loadbytes
row noexit "noexit.bpf.lua:8: a loop with no exit cannot be compiled" \
	$'\tlocal s = 0\n\twhile true do\n\t\ts = s + one\n\tend\n\treturn s'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

