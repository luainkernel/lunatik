#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Records what each corpus object costs the verifier, so a regression in the emitted shape is
# caught here rather than against the million-instruction limit.
#   - the "processed N insns" figure the verifier's log prints for the heaviest program of each
#     corpus is reported as a KTAP comment and asserted under a ceiling
# The ceiling is set from what was measured, not predicted; the figures are in
# doc/design/luaebpf/plan.md.
#
# Usage: sudo bash tests/luaebpf/budget.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

CEILING=20000

CORPORA="pass arith divzero branch forconst forvar call ctx packet bounds getstring strcmp mapget mapset struct"

luaebpf_start 1

# the escape hatch's own cost, where the module publishes the kfunc its programs call
[ -z "$(luaebpf_kfunc luaxdp bpf_luaxdp_run)" ] && CORPORA="$CORPORA callback"

worst=0
for name in $CORPORA; do
	output=$(luaebpf_compile "$name") || { comment "$output"; fail "luaebpf: $name.bpf.lua did not compile"; }
	log=$(luaebpf_verbose "$name")
	rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
	most=$(echo "$log" | grep -oP 'processed \K[0-9]+' | sort -n | tail -1)
	[ -n "$most" ] || { comment "$log"; fail "luaebpf: $name printed no instruction count"; }
	comment "$name: $most insns processed, worst program of the corpus"
	[ "$most" -gt "$worst" ] && worst=$most
done

[ "$worst" -le "$CEILING" ] || fail "luaebpf: the worst corpus program cost $worst insns, over the $CEILING ceiling"
ktap_pass "luaebpf: every corpus program verifies under $CEILING processed instructions"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

