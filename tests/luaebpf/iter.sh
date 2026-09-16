#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the lowering a kernel with the open-coded iterators and without may_goto takes: the
# loops of while.sh plus a return out of a loop body, a check that fails inside one, a loop whose
# head is entered by a jump rather than by a fall-through, a `repeat` whose body opens with a loop
# of its own, and a numeric `for` the compiler cannot bound, compiled with LUAEBPF_PROBE naming
# the iterators.
#   - the object's BTF names bpf_iter_num_new, bpf_iter_num_next and bpf_iter_num_destroy, and
#     the loaded program calls them
#   - every program loads. That is the assertion the return, the break, the nested pair, the
#     failing check and the loop entered by a jump rest on: an iterator still live where the
#     program exits is an unreleased reference the verifier refuses, and a head an edge reaches
#     below its own creation asks for a next of an iterator nothing made, so loading at all is
#     what says every edge in created one and every path out destroyed the one it left, and that
#     two back edges landing on one head share the one iterator that head makes
#   - every row answers what the interpreter answers, or the program's default where it raises
#   - the same file compiled without the override names no iterator, since this kernel has
#     may_goto and the compiler asks it: the override is what runs the other lowering here
# On a kernel whose BTF publishes no bpf_iter_num_new the case skips with that reason.
#
# Usage: sudo bash tests/luaebpf/iter.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ITERATORS="loadbytes,iter"
ROWS=4

luaebpf_start "$ROWS"

gate=$(luaebpf_kfunc vmlinux bpf_iter_num_new)
[ -n "$gate" ] && luaebpf_skipall "$ROWS" "$gate"

output=$(luaebpf_compile iter "" "$ITERATORS") \
	|| { comment "$output"; fail "luaebpf: iter.bpf.lua did not compile"; }

named=$(bpftool btf dump file "$LUAEBPF_WORK/iter.bpf.o" format raw 2>&1)
for kfunc in bpf_iter_num_new bpf_iter_num_next bpf_iter_num_destroy; do
	echo "$named" | grep -q "FUNC '$kfunc'" || fail "luaebpf: the object does not name $kfunc"
done
ktap_pass "luaebpf: the object names the three iterator kfuncs it calls"

output=$(luaebpf_loadall iter) || { comment "$output"; fail "luaebpf: the iterator loops did not verify"; }
for name in returned1 broken2 nested2 aborted1 jumped2 gated2 sharedhead2; do
	[ -e "$LUAEBPF_PINS/$name" ] || fail "luaebpf: $name did not verify"
done
ktap_pass "luaebpf: every edge into a loop creates its iterator and every path out destroys it"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: an iterator loop differs from the interpreter"; }
ktap_pass "luaebpf: every loop terminates with the interpreter's answer"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile iter) || { comment "$output"; fail "luaebpf: the unforced build failed"; }
bpftool btf dump file "$LUAEBPF_WORK/iter.bpf.o" format raw 2>&1 | grep -q "bpf_iter_num" \
	&& fail "luaebpf: a kernel with may_goto still took the iterator lowering"
ktap_pass "luaebpf: the lowering is the probe's answer, and the override is what changed it"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

