#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the phase 0 bench, tools/bench/xdp.sh, and reports its table as KTAP comments.
#   - the script is looked for where tests_install puts it and in the source tree, and the case
#     skips naming it where it is in neither, which is this tree: tools/bench/ arrives with
#     claude_luaebpf_bench, which claude_luaebpf_examples is not stacked on
#   - where it is there, the bench runs with a one-second window and a single run per row and the
#     case passes when every row of its table produced a packets-per-second figure
# Informational, never a gate: a rate measured under a one-second window is not the figure the
# documents quote, which comes from a full manual run. The case was proved on a worktree merging
# claude_luaebpf_bench into claude_luaebpf_examples, with the compiled filter's row added to that
# script's `rows` array; the merge is not this branch's to carry, so here the case skips.
#
# Usage: sudo bash tests/luaebpf/example_speed.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

BENCH=tools/bench/xdp.sh
WINDOW=1
RUNS=1
PLAN=1

luaebpf_start "$PLAN"

script=
for candidate in "$DIR/../bench/xdp.sh" "$DIR/../../$BENCH"; do
	[ -r "$candidate" ] && { script=$candidate; break; }
done
[ -n "$script" ] || luaebpf_skipall "$PLAN" "$BENCH is not in this tree"

output=$(LUNATIK_BENCH_SECONDS=$WINDOW LUNATIK_BENCH_RUNS=$RUNS bash "$script" 2>&1)
status=$?
comment "$output"
[ "$status" -eq 0 ] || fail "luaebpf: $BENCH exited $status"

# the table's own rows, which are the lines between its header and the blank line that ends it,
# each owing a packets-per-second figure. That figure is read out of the column the header's own
# "pps" ends in, since more than one column carries a decimal and a label carries spaces
read -r rows rated <<< "$(echo "$output" | awk '
	/^row +context/ { table = 1; at = index($0, "pps") + 2; next }
	table && NF == 0 { exit }
	table { rows++; n = split(substr($0, 1, at), column, / +/); if (column[n] + 0 > 0) rated++ }
	END { printf "%d %d\n", rows + 0, rated + 0 }')"

[ "$rows" -gt 0 ] || fail "luaebpf: $BENCH printed no table"
[ "$rows" -eq "$rated" ] || fail "luaebpf: $((rows - rated)) of $rows bench rows produced no rate"
ktap_pass "luaebpf: every row of the phase 0 bench produced a rate"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

